import Foundation
import Observation
import FreeCellEngine

/// The only object that changes game state. Views call its intents and never mutate state
/// themselves; every change the player makes pushes an undo snapshot first.
@Observable @MainActor
final class GameStore {
    static let undoLimit = 300
    /// The pause between automatic plays and Finish steps (spec "Layout and visuals").
    static let autoStep: Duration = .milliseconds(90)

    private(set) var state: GameState {
        didSet {
            let moved = Self.movedCards(from: oldValue, to: state)
            if !moved.isEmpty {
                movedCardIDs = moved
                // Any change that moves cards (undo, an automatic play, a Finish step, a resume)
                // ends a drag in progress — the card it held may not be where it was. The clock's
                // tick moves nothing and leaves the drag alone.
                pendingDrag = nil
            }
            if Self.shouldSave(from: oldValue, to: state) { scheduleSave() }
        }
    }
    /// This deal's identity: new for every deal — a new game, a restart (the same number again) or
    /// a resume — so the win card and the win animation belong to one playing of a game.
    private(set) var dealID = UUID()
    /// The cards the latest change moved between piles. The board raises them above everything
    /// while they animate, so they never slide under a deeper column.
    private(set) var movedCardIDs: Set<Int> = []
    /// Whether the last deal (or the game resumed) is Hard Core: what New Game deals next.
    /// Remembered straight away; only dealing changes it.
    private(set) var lastHardCore: Bool {
        didSet { if lastHardCore != oldValue { rememberHardCore?(lastHardCore) } }
    }
    @ObservationIgnored var rememberHardCore: ((Bool) -> Void)?
    /// Whether the last deal (or the game resumed) is Relaxed: what New Game deals next.
    private(set) var lastRelaxed: Bool {
        didSet { if lastRelaxed != oldValue { rememberRelaxed?(lastRelaxed) } }
    }
    @ObservationIgnored var rememberRelaxed: ((Bool) -> Void)?
    /// Why the last drag or tap didn't move (spec "Interaction"): a run longer than the free spaces
    /// allow. The board shows it for a moment; nil otherwise.
    private(set) var notice: Notice?

    struct Notice: Equatable {
        let text: String
        let sequence: Int                 // a repeat of the same refusal still shows again
    }
    /// Settings ▸ Play cards home automatically (spec "Game rules"); tests set it directly.
    @ObservationIgnored var playsCardsHome: () -> Bool = { true }
    /// Whether automatic plays and Finish step 90 ms apart (the board turns this off under Reduce
    /// Motion; tests turn it off to settle at once).
    @ObservationIgnored var animatesAutomaticPlays = true
    /// Called once when the game is won (spec "Scores": the app records it) — not for a restarted
    /// game, which never counts (spec "Restart").
    @ObservationIgnored var onWin: ((GameState) -> Void)?
    /// The card being dragged (with the cards below it), from `beginDrag` until `drop` or `cancelDrag`.
    private(set) var pendingDrag: PendingDrag?
    /// The latest thing worth a haptic (iOS): a move or a win. Nothing on failure.
    private(set) var feedback: FeedbackEvent?

    struct PendingDrag: Equatable {
        let source: PileID
        let index: Int
    }

    struct FeedbackEvent: Equatable {
        enum Kind: Equatable { case move, win }
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
    @ObservationIgnored private let makeNumber: () -> Int
    @ObservationIgnored private var clock: Task<Void, Never>?
    /// Automatic plays after a move, or Finish: one card home every `autoStep`.
    @ObservationIgnored private var stepping: Task<Void, Never>?
    @ObservationIgnored private var steppingIsFinish = false

    /// - Parameter makeNumber: where New Game's numbers come from; tests inject a fixed sequence.
    init(hardCore: Bool = false, relaxed: Bool = false, makeNumber: @escaping () -> Int = GameStore.randomNumber) {
        self.makeNumber = makeNumber
        lastHardCore = hardCore
        lastRelaxed = relaxed
        state = FreeCellEngine.newGame(number: makeNumber(), hardCore: hardCore, relaxed: relaxed)
    }

    nonisolated static func randomNumber() -> Int {
        var generator = SystemRandomNumberGenerator()
        return FreeCellEngine.randomNumber(using: &generator)
    }

    /// Nothing undoes a win: a won game cannot be un-won (spec decision).
    var canUndo: Bool { !undoStack.isEmpty && !state.isWon }
    var canAutoFinish: Bool { FreeCellEngine.canAutoFinish(state) }
    /// Restart has something to do once a move has been made (a fresh deal is already the start).
    var canRestart: Bool { state.moveCount > 0 }
    /// A game the player would lose by dealing again: a move made, and not won. Only such a game is
    /// asked about before a new deal replaces it.
    var isInProgress: Bool { state.moveCount > 0 && !state.isWon }

    // MARK: Intents

    /// Deals a random game number (never one of the eight unwinnable). `hardCore`, `relaxed`: nil
    /// keeps the last deal's mode.
    func newGame(hardCore: Bool? = nil, relaxed: Bool? = nil) {
        newGame(number: makeNumber(), hardCore: hardCore, relaxed: relaxed)
    }

    /// Deals game `number` (clamped into range). `hardCore`, `relaxed`: nil keeps the last deal's mode.
    func newGame(number: Int, hardCore: Bool? = nil, relaxed: Bool? = nil) {
        stopStepping()
        pendingDrag = nil
        notice = nil
        lastHardCore = hardCore ?? lastHardCore
        lastRelaxed = relaxed ?? lastRelaxed
        let n = min(max(number, FreeCellEngine.numbers.lowerBound), FreeCellEngine.numbers.upperBound)
        state = FreeCellEngine.newGame(number: n, hardCore: lastHardCore, relaxed: lastRelaxed)
        dealID = UUID()
        undoStack.removeAll()
        updateClock()
    }

    /// Deals this game again from the start (spec "Restart"); its win is never recorded.
    func restart() {
        guard canRestart else { return }
        stopStepping()
        pendingDrag = nil
        state = FreeCellEngine.restart(state)
        dealID = UUID()
        undoStack.removeAll()
        updateClock()
    }

    /// Continues a game from a given state (a saved game, or a test position). Undo starts empty.
    func resume(from saved: GameState) {
        stopStepping()
        lastHardCore = saved.isHardCore
        lastRelaxed = saved.isRelaxed
        state = saved
        dealID = UUID()
        undoStack.removeAll()
        updateClock()
    }

    /// Tap or click on a card: sends it (with the cards below it) to the best legal destination.
    /// Returns false when nothing can move, so the view can wiggle instead.
    @discardableResult
    func tap(pile: PileID, index: Int) -> Bool {
        settleNow()
        guard let destination = FreeCellEngine.autoDestination(for: pile, index: index, in: state) else {
            explain(FreeCellEngine.runLimitRefusal(for: pile, index: index, in: state))
            return false
        }
        perform(Move(source: pile, index: index, destination: destination))
        return true
    }

    /// A drag has passed its threshold on this card. Returns false (and holds nothing) for a card
    /// that cannot be picked up: on a foundation, or under an out-of-order card.
    @discardableResult
    func beginDrag(pile: PileID, index: Int) -> Bool {
        settleNow()
        guard FreeCellEngine.canPickUp(from: pile, index: index, in: state) else { return false }
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
        settleNow()
        let move = Move(source: source, index: index, destination: destination)
        guard FreeCellEngine.canMove(move, in: state) else {
            explain(FreeCellEngine.runLimitRefusal(move, in: state))
            return false
        }
        perform(move)
        return true
    }

    /// Takes back the last move — with the automatic plays it set off — or the last Finish step.
    /// The clock keeps its time and the undo is counted, so undoing never earns back time.
    func undo() {
        guard canUndo, var previous = undoStack.popLast() else { return }
        stopStepping()
        previous.elapsed = state.elapsed
        previous.undos = state.undos + 1
        state = previous
        updateClock()
    }

    /// Plays every remaining card home, lowest first, one every 90 ms; each step is its own undo
    /// step and costs no move.
    func autoFinish() {
        guard canAutoFinish, !isAutoFinishing else { return }
        settleNow()
        guard canAutoFinish else { return }
        step(finishing: true)
    }

    // MARK: Clock

    /// The game has started once the player has made a move.
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

    // MARK: Automatic plays and Finish

    /// True while Finish is sending cards home.
    var isAutoFinishing: Bool { stepping != nil && steppingIsFinish }

    /// Stops automatic plays or Finish where they are (a new deal, a resume, undo, or a question
    /// card); Finish stays available to start again.
    func stopAutoFinish() {
        stopStepping()
    }

    private func stopStepping() {
        stepping?.cancel()
        stepping = nil
        steppingIsFinish = false
    }

    /// The next card the game plays by itself: a Finish step, or an automatic play home.
    private func nextAutomatic(finishing: Bool) -> Move? {
        finishing ? FreeCellEngine.nextAutoFinishMove(in: state)
                  : (playsCardsHome() ? FreeCellEngine.nextSafePlay(in: state) : nil)
    }

    /// Plays the game's own moves: at once without animation, else one every `autoStep`.
    private func step(finishing: Bool) {
        stopStepping()
        guard nextAutomatic(finishing: finishing) != nil else { return }
        guard animatesAutomaticPlays else {
            while let move = nextAutomatic(finishing: finishing) { playAutomatic(move, finishing: finishing) }
            return
        }
        steppingIsFinish = finishing
        stepping = Task { [weak self] in
            while let self, !Task.isCancelled, let move = self.nextAutomatic(finishing: finishing) {
                try? await Task.sleep(for: Self.autoStep)
                guard !Task.isCancelled else { return }
                self.playAutomatic(move, finishing: finishing)
            }
            // A cancelled run must not clear the handle of a run started after it.
            if !Task.isCancelled { self?.stepping = nil; self?.steppingIsFinish = false }
        }
    }

    /// Plays any automatic plays still waiting, at once — so a new move never races them.
    private func settleNow() {
        guard stepping != nil, !steppingIsFinish else { return }
        stopStepping()
        while let move = nextAutomatic(finishing: false) { playAutomatic(move, finishing: false) }
    }

    private func playAutomatic(_ move: Move, finishing: Bool) {
        guard FreeCellEngine.canMove(move, in: state) else { return }
        if finishing { record() }                           // each Finish step undoes on its own
        FreeCellEngine.applyAutomatic(move, to: &state)
        afterChange()
    }

    // MARK: Helpers

    private func perform(_ move: Move) {
        record()
        FreeCellEngine.apply(move, to: &state)
        afterChange()
        if !state.isWon { step(finishing: false) }
    }

    /// Feedback, the win, and the clock after any change.
    private func afterChange() {
        announce(state.isWon ? .win : .move)
        if state.isWon && !state.isRestarted { onWin?(state) }
        updateClock()
    }

    /// Shows why a run didn't move, when the run limit is why.
    private func explain(_ refusal: FreeCellEngine.RunLimitRefusal?) {
        guard let refusal else { return }
        notice = Notice(text: Self.noticeText(refusal), sequence: (notice?.sequence ?? 0) + 1)
    }

    /// "Only 2 cards can move — 1 free cell, no empty column" (spec "Interaction").
    nonisolated static func noticeText(_ r: FreeCellEngine.RunLimitRefusal) -> String {
        let cards = r.limit == 1 ? "Only 1 card can move" : "Only \(r.limit) cards can move"
        let place = r.intoEmptyColumn ? " into an empty column" : ""
        let cells = r.emptyCells == 0 ? "no free cell" : r.emptyCells == 1 ? "1 free cell" : "\(r.emptyCells) free cells"
        let other = r.intoEmptyColumn ? "other " : ""
        let columns = r.emptyColumns == 0 ? "no \(other)empty column"
            : r.emptyColumns == 1 ? "1 \(other)empty column" : "\(r.emptyColumns) \(other)empty columns"
        return "\(cards)\(place) — \(cells), \(columns)"
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

    // MARK: Saving

    /// Save after every applied change, and, while only the clock runs, on every fifth second.
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
    /// right after. Safe to block the main thread: save tasks run off the main actor.
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
        lastSave = Task.detached {
            await previous?.value
            try? await saver.save(snapshot, sequence: sequence)
        }
    }

    /// The store the app starts with: the saved game resumed, or a fresh deal — which is saved at
    /// once, so an older save left on disk can never come back later.
    static func launch(_ plan: LaunchPlan, saver: GameSaver?) -> GameStore {
        let store: GameStore
        switch plan {
        case .resume(let saved):
            store = GameStore(hardCore: saved.isHardCore, relaxed: saved.isRelaxed)
            store.resume(from: saved)
            store.saver = saver
        case .deal(let hardCore, let relaxed):
            store = GameStore(hardCore: hardCore, relaxed: relaxed)
            store.saver = saver
            store.saveNow()
        }
        return store
    }

    nonisolated static func movedCards(from old: GameState, to new: GameState) -> Set<Int> {
        func piles(_ s: GameState) -> [Int: PileID] {
            var out: [Int: PileID] = [:]
            for (i, c) in s.cells.enumerated() { if let c { out[c.id] = .cell(i) } }
            for (f, pile) in s.foundations.enumerated() { for c in pile { out[c.id] = .foundation(f) } }
            for (t, pile) in s.tableau.enumerated() { for c in pile { out[c.id] = .tableau(t) } }
            return out
        }
        let before = piles(old)
        return Set(piles(new).compactMap { id, pile in before[id] == pile ? nil : id })
    }
}
