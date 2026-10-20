import Foundation
import Observation
import SolitaireEngine

/// The only object that changes game state. Views call its intents and never mutate state
/// themselves; every change pushes an undo snapshot first.
@Observable @MainActor
final class GameStore {
    static let undoLimit = 300
    static let autoFinishStep: Duration = .milliseconds(90)

    private(set) var state: GameState {
        didSet {
            let moved = Self.movedCards(from: oldValue, to: state)
            if !moved.isEmpty {
                movedCardIDs = moved
                // Any change that moves cards (undo, a draw, an auto-finish step, a resume) ends a
                // drag in progress — the card it held may not be where it was. The clock's tick
                // moves nothing and leaves the drag alone.
                pendingDrag = nil
            }
            if Self.shouldSave(from: oldValue, to: state) { scheduleSave() }
        }
    }
    /// The cards the latest change moved between piles (a move, draw, redeal, undo or deal). The
    /// board raises them above everything while they animate, so they never slide under a deeper
    /// column; the clock ticking does not reset it.
    private(set) var movedCardIDs: Set<Int> = []
    /// The draw mode of the last deal (or of the game resumed): what New Game deals next and what a
    /// fresh launch deals. Every change is remembered straight away, whether or not a game window
    /// is open. Only dealing changes it — the draw chip switches mode by dealing (spec "New games
    /// and the draw mode").
    private(set) var lastDrawCount: Int {
        didSet { if lastDrawCount != oldValue { rememberDrawCount?(lastDrawCount) } }
    }
    /// Stores the draw-count setting (UserDefaults in the app; nil in tests).
    @ObservationIgnored var rememberDrawCount: ((Int) -> Void)?
    /// Whether the last deal (or the game resumed) is Hard Core: what New Game deals next.
    /// Remembered straight away, like the draw count; only dealing changes it.
    private(set) var lastHardCore: Bool {
        didSet { if lastHardCore != oldValue { rememberHardCore?(lastHardCore) } }
    }
    @ObservationIgnored var rememberHardCore: ((Bool) -> Void)?
    /// Called once when a move wins the game (spec "Scores": the app records it) — not for a
    /// restarted game, which never counts (spec "Restart").
    @ObservationIgnored var onWin: ((GameState) -> Void)?
    /// The card being dragged (with its run), from `beginDrag` until `drop` or `cancelDrag`.
    private(set) var pendingDrag: PendingDrag?
    /// The latest thing worth a haptic (iOS): a move, a draw, a win. Nothing on failure.
    private(set) var feedback: FeedbackEvent?

    struct PendingDrag: Equatable {
        let source: PileID
        let index: Int
    }

    struct FeedbackEvent: Equatable {
        enum Kind: Equatable { case move, draw, win }
        let kind: Kind
        let sequence: Int                 // distinguishes two identical events in a row
    }
    private(set) var undoStack: [GameState] = []
    /// True while the app is in the foreground; the clock only runs then.
    var isActive = true {
        didSet { updateClock() }
    }

    /// Where the game is saved; nil (tests, the unit-test host) means no persistence.
    @ObservationIgnored var saver: GameSaver?
    @ObservationIgnored private var saveSequence = 0
    /// The latest save in flight; each waits for the one before it.
    @ObservationIgnored private(set) var lastSave: Task<Void, Never>?
    @ObservationIgnored private let makeSeed: () -> UInt64
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var finishing: Task<Void, Never>?

    /// - Parameter makeSeed: where deal seeds come from; tests inject a fixed sequence.
    init(drawCount: Int = 1, hardCore: Bool = false,
         makeSeed: @escaping () -> UInt64 = { UInt64.random(in: .min ... .max) }) {
        self.makeSeed = makeSeed
        lastDrawCount = Self.validDrawCount(drawCount)
        lastHardCore = hardCore
        state = SolitaireEngine.newGame(drawCount: Self.validDrawCount(drawCount), seed: makeSeed(),
                                        hardCore: hardCore)
    }

    /// Nothing undoes a win: a won game cannot be un-won (spec decision).
    var canUndo: Bool { !undoStack.isEmpty && !state.isWon }
    var canAutoFinish: Bool { SolitaireEngine.canAutoFinish(state) }
    /// The live score (spec "Scoring"): the play score, and the time bonus once won.
    var score: Int { SolitaireEngine.score(state) }
    var playScore: Int { SolitaireEngine.playScore(state) }
    var timeBonus: Int {
        state.isWon && !state.isRestarted ? SolitaireEngine.timeBonus(seconds: Int(state.elapsed)) : 0
    }
    /// Restart has something to do once a move has been made (a fresh deal is already the start).
    var canRestart: Bool { state.moveCount > 0 }
    /// A game the player would lose by dealing again: a move (a draw included) made, and not won.
    /// Only such a game is asked about before a new deal replaces it.
    var isInProgress: Bool { state.moveCount > 0 && !state.isWon }

    // MARK: Intents

    /// Deals a new game in the remembered draw mode.
    func newGame() {
        newGame(drawCount: lastDrawCount)
    }

    /// Deals a new game. An out-of-range draw count (e.g. a corrupted setting) becomes 1; the
    /// choice is remembered for the next deal.
    /// `hardCore`: nil keeps the last deal's Hard Core mode.
    func newGame(drawCount: Int, hardCore: Bool? = nil) {
        stopAutoFinish()
        pendingDrag = nil
        lastDrawCount = Self.validDrawCount(drawCount)
        lastHardCore = hardCore ?? lastHardCore
        state = SolitaireEngine.newGame(drawCount: lastDrawCount, seed: makeSeed(), hardCore: lastHardCore)
        undoStack.removeAll()
        updateClock()
    }

    /// Deals this game again from the start (spec "Restart"); it scores 0 until a new game.
    func restart() {
        guard canRestart else { return }
        stopAutoFinish()
        pendingDrag = nil
        state = SolitaireEngine.restart(state)
        undoStack.removeAll()
        updateClock()
    }

    /// Continues a game from a given state (a saved game, or a test position). Undo starts empty.
    func resume(from saved: GameState) {
        stopAutoFinish()
        lastDrawCount = Self.validDrawCount(saved.drawCount)
        lastHardCore = saved.isHardCore
        state = saved
        undoStack.removeAll()
        updateClock()
    }

    /// Tap or click on a card: sends it (with its run) to the best legal destination.
    /// Returns false when nothing can move, so the view can wiggle instead.
    @discardableResult
    func tap(pile: PileID, index: Int) -> Bool {
        guard let destination = SolitaireEngine.autoDestination(for: pile, index: index, in: state) else {
            return false
        }
        perform(Move(source: pile, index: index, destination: destination))
        return true
    }

    /// A drag has passed its threshold on this card. Returns false (and holds nothing) for a card
    /// that cannot be picked up: face down, buried in the waste or a foundation, or the stock.
    @discardableResult
    func beginDrag(pile: PileID, index: Int) -> Bool {
        guard SolitaireEngine.canPickUp(from: pile, index: index, in: state) else { return false }
        pendingDrag = PendingDrag(source: pile, index: index)
        return true
    }

    func cancelDrag() {
        pendingDrag = nil
    }

    /// A drag released over `destination`. Returns false for an illegal drop (the card springs back).
    @discardableResult
    func drop(source: PileID, index: Int, on destination: PileID) -> Bool {
        pendingDrag = nil
        let move = Move(source: source, index: index, destination: destination)
        guard SolitaireEngine.canMove(move, in: state) else { return false }
        perform(move)
        return true
    }

    /// Tap on the stock: draw, or redeal when the stock is empty.
    func tapStock() {
        guard !state.isWon, !(state.stock.isEmpty && state.waste.isEmpty) else { return }
        record()
        SolitaireEngine.drawFromStock(&state)
        announce(.draw)
        updateClock()
    }

    /// Takes back the last change: board, moves and passes as they were — but the clock keeps its
    /// time and the undo is counted (spec "Scoring"), so undoing never earns back time or points.
    func undo() {
        guard canUndo, var previous = undoStack.popLast() else { return }
        stopAutoFinish()
        previous.elapsed = state.elapsed
        previous.undos = state.undos + 1
        state = previous
        updateClock()
    }

    /// Plays the rest of the game to the foundations, one normal (undoable) move every 90 ms.
    func autoFinish() {
        guard canAutoFinish, finishing == nil else { return }
        finishing = Task { [weak self] in
            while let self, !Task.isCancelled, let move = SolitaireEngine.nextAutoFinishMove(in: self.state) {
                self.perform(move)
                try? await Task.sleep(for: Self.autoFinishStep)
            }
            // A cancelled run must not clear the handle of a run started after it.
            if !Task.isCancelled { self?.finishing = nil }
        }
    }

    // MARK: Clock

    /// The game has started once the player has done something.
    var isRunning: Bool { isActive && !state.isWon && state.moveCount > 0 }

    /// One second of play. Called by the clock; tests call it directly.
    func tick() {
        guard isRunning else { return }
        state.elapsed += 1
    }

    private func updateClock() {
        if isRunning, clock == nil {
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    self.tick()
                }
            }
        } else if !isRunning {
            clock?.cancel()
            clock = nil
        }
    }

    // MARK: Helpers

    private func perform(_ move: Move) {
        record()
        SolitaireEngine.apply(move, to: &state)
        announce(state.isWon ? .win : .move)
        if state.isWon && !state.isRestarted { onWin?(state) }
        updateClock()
    }

    private func announce(_ kind: FeedbackEvent.Kind) {
        feedback = FeedbackEvent(kind: kind, sequence: (feedback?.sequence ?? 0) + 1)
    }

    /// Snapshot the state before a change; the oldest snapshot falls off past the limit.
    private func record() {
        undoStack.append(state)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
    }

    /// True while auto-finish is sending cards home.
    var isAutoFinishing: Bool { finishing != nil }

    /// Stops auto-finish where it is (a new deal, a resume, or the new-game question); Finish
    /// stays available to start it again.
    func stopAutoFinish() {
        finishing?.cancel()
        finishing = nil
    }

    // MARK: Saving

    /// Save after every applied change — a move, draw, redeal, undo, deal or resume — and, while
    /// only the clock runs, on every fifth second (spec).
    nonisolated static func shouldSave(from old: GameState, to new: GameState) -> Bool {
        var oldIgnoringClock = old
        oldIgnoringClock.elapsed = new.elapsed
        if oldIgnoringClock != new { return true }
        return old.elapsed != new.elapsed && Int(new.elapsed) % 5 == 0
    }

    /// Save now, whatever changed.
    func saveNow() {
        scheduleSave()
    }

    /// Save now and wait (up to `timeout`) until it is on disk — for moments the process may end
    /// right after: quitting on the Mac, going to the background on iOS. Safe to block the main
    /// thread: save tasks run off the main actor.
    func flushSaves(timeout: TimeInterval = 2) {
        guard saver != nil else { return }
        scheduleSave()
        let pending = lastSave
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await pending?.value
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    private func scheduleSave() {
        guard let saver else { return }
        saveSequence += 1
        let (snapshot, sequence, previous) = (state, saveSequence, lastSave)
        // Detached: the write never needs the main actor, so `flushSaves` can wait on it.
        lastSave = Task.detached {
            await previous?.value
            try? await saver.save(snapshot, sequence: sequence)
        }
    }

    /// The store the app starts with: the saved game resumed, or a fresh deal — which is saved at
    /// once, so an older save left on disk can never come back later.
    static func launch(_ plan: LaunchPlan, drawCount: Int, saver: GameSaver?) -> GameStore {
        let store: GameStore
        switch plan {
        case .resume(let saved):
            store = GameStore(drawCount: drawCount)
            store.resume(from: saved)
            store.saver = saver
        case .deal(let count, let hardCore):
            store = GameStore(drawCount: count, hardCore: hardCore)
            store.saver = saver
            store.saveNow()
        }
        return store
    }

    nonisolated static func movedCards(from old: GameState, to new: GameState) -> Set<Int> {
        func piles(_ s: GameState) -> [Int: PileID] {
            var out: [Int: PileID] = [:]
            for c in s.stock { out[c.id] = .stock }
            for c in s.waste { out[c.id] = .waste }
            for (f, pile) in s.foundations.enumerated() { for c in pile { out[c.id] = .foundation(f) } }
            for (t, pile) in s.tableau.enumerated() { for c in pile { out[c.id] = .tableau(t) } }
            return out
        }
        let before = piles(old)
        return Set(piles(new).compactMap { id, pile in before[id] == pile ? nil : id })
    }

    nonisolated static func validDrawCount(_ drawCount: Int) -> Int {
        drawCount == 3 ? 3 : 1
    }
}
