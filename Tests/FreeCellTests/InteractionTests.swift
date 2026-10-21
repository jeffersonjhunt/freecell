import CoreGraphics
import Foundation
import Testing
import FreeCellEngine
@testable import FreeCell

/// Makes some legal move on the store (the first the rules list), so a game is in progress.
@MainActor
func playAMove(_ store: GameStore) {
    let move = legalMoves(store.state).first!
    #expect(store.drop(source: move.source, index: move.index, on: move.destination))
}

/// Cards for filling piles in a hand-built position, none of them in `excluding`.
func fillers(excluding used: [Card]) -> [Card] {
    let taken = Set(used)
    return Suit.allCases.flatMap { s in (1...13).map { Card(suit: s, rank: $0) } }.filter { !taken.contains($0) }
}

@MainActor @Suite struct Dragging {
    @Test func onlyMovableCardsStartADrag() {
        let store = makeStore(at: position(columns: [cards("8S 3H")], foundations: [cards("AS")]))
        #expect(!store.beginDrag(pile: .tableau(0), index: 0), "under an out-of-order card")
        #expect(!store.beginDrag(pile: .foundation(0), index: 0), "home stays home")
        #expect(store.pendingDrag == nil)
        #expect(store.beginDrag(pile: .tableau(0), index: 1))
        #expect(store.pendingDrag == GameStore.PendingDrag(source: .tableau(0), index: 1))
        store.cancelDrag()
        #expect(store.pendingDrag == nil)
    }

    /// Undo or any other change that moves cards ends a drag in progress; the clock's tick doesn't.
    @Test func changesThatMoveCardsEndADrag() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C"), cards("QS")]))
        #expect(store.tap(pile: .tableau(0), index: 1))
        #expect(store.beginDrag(pile: .tableau(2), index: 0))
        store.tick()
        #expect(store.pendingDrag != nil, "a tick moves nothing")
        store.undo()
        #expect(store.pendingDrag == nil, "undo ends it")
        #expect(store.beginDrag(pile: .tableau(2), index: 0))
        store.resume(from: store.state)
        #expect(store.pendingDrag != nil, "resuming the same position moves nothing")
        store.newGame()
        #expect(store.pendingDrag == nil)
    }

    @Test func aDropEndsTheDragLegalOrNot() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C"), cards("QH")]))
        #expect(store.beginDrag(pile: .tableau(0), index: 1))
        #expect(store.drop(source: .tableau(0), index: 1, on: .tableau(1)))
        #expect(store.pendingDrag == nil)
        #expect(store.beginDrag(pile: .tableau(2), index: 0))
        let before = store.state
        #expect(!store.drop(source: .tableau(2), index: 0, on: .tableau(0)), "a red queen on a red king")
        #expect(store.pendingDrag == nil && store.state == before)
    }

    /// A run too long for the free spaces lifts, but the drop is refused and nothing changes.
    @Test func aRunTooLongForTheFreeSpacesSpringsBack() {
        let run = cards("9C 8H 7S"), target = cards("TD")
        var spare = fillers(excluding: run + target)
        let cells: [Card?] = (0..<4).map { _ in spare.removeFirst() }                 // every cell full
        let others = (0..<6).map { _ in [spare.removeFirst()] }                       // no empty column
        let store = makeStore(at: position(columns: [run, target] + others, cells: cells))
        #expect(store.beginDrag(pile: .tableau(0), index: 0))
        let before = store.state
        #expect(!store.drop(source: .tableau(0), index: 0, on: .tableau(1)), "one card at a time with no free space")
        #expect(store.state == before)
        #expect(store.drop(source: .tableau(0), index: 2, on: .tableau(1)) == false, "7♠ on 10♦: not a fit")
    }
}

/// Spec "New games": New Game deals a random number at once unless a game in progress would be
/// lost; then it asks. Choose a game's Play is its own confirmation.
@MainActor @Suite struct NewGames {
    @Test func aFreshDealIsReplacedAtOnce() {
        let store = makeStore()
        let ui = AppUI()
        #expect(!store.isInProgress && store.state.number == 617)
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame == nil && store.state.number == 618)
    }

    @Test func aGameInProgressIsAskedAboutAndKeptUntilConfirmed() {
        let store = makeStore()
        let ui = AppUI()
        playAMove(store)
        #expect(store.isInProgress)
        let before = store.state
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame == NewGameRequest(number: nil, hardCore: false))
        #expect(ui.pendingNewGame?.title == "Start a new game?" && ui.pendingNewGame?.message == "This one will be lost.")
        #expect(ui.pendingNewGame?.kicker == "NEW GAME" && ui.pendingNewGame?.confirm == "New Game")
        #expect(store.state == before, "nothing dealt yet")
        ui.confirmPending(store: store)
        #expect(ui.pendingNewGame == nil && store.state.number == 618 && store.state.moveCount == 0)
    }

    /// Choose a game: Play deals that number at once, mid-game too (the card said the game ends).
    @Test func choosingAGameDealsThatNumber() {
        let store = makeStore()
        let ui = AppUI()
        playAMove(store)
        ui.requestNewGame(number: 11982, confirmed: true, store: store)
        #expect(ui.pendingNewGame == nil && store.state.number == 11982 && store.state.moveCount == 0)
        ui.requestNewGame(confirmed: true, store: store)                         // Random game
        #expect(store.state.number == 618, "the store's next random number")
    }

    @Test(arguments: [("617", 617), (" 42 ", 42), ("1", 1), ("1000000", 1_000_000), ("0", nil), ("1000001", nil),
                      ("", nil), ("abc", nil), ("6 17", nil), ("-5", nil), ("٦١٧", nil)] as [(String, Int?)])
    func theGameNumberFieldAcceptsOnlyGameNumbers(text: String, number: Int?) {
        #expect(ChooseGameCard.number(from: text) == number)
    }

    @Test func aWonGameIsReplacedAtOnce() {
        var won = position(columns: [], foundations: Suit.allCases.map { foundation($0, upTo: 13) })
        won.isWon = true
        won.moveCount = 90
        let store = makeStore(at: won)
        let ui = AppUI()
        #expect(!store.isInProgress, "won: nothing to lose")
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame == nil && !store.state.isWon)
    }

    /// Asking stops Finish: no card flies home behind the question, and the game cannot be won
    /// there. Finish is still offered afterwards.
    @Test func askingStopsFinish() async {
        var s = UITestScenario.state(named: "almostWon")!
        s.moveCount = 40
        let store = makeStore(at: s, animated: true)
        store.autoFinish()
        #expect(store.isAutoFinishing)
        let ui = AppUI()
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame != nil && !store.isAutoFinishing)
        let home = store.state.foundations.map(\.count)
        try? await Task.sleep(for: GameStore.autoStep * 4)
        #expect(store.state.foundations.map(\.count) == home && !store.state.isWon, "nothing more went home")
        #expect(store.canAutoFinish, "Finish is offered again")
    }

    @Test func withAskingOffAGameInProgressIsReplacedAtOnce() {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { false }
        playAMove(store)
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame == nil && store.state.number == 618 && store.state.moveCount == 0)
    }

    /// Asking is the default: unset, or anything that isn't a yes/no, reads as yes.
    @Test func askingIsTheDefault() throws {
        let name = "ask-before-ending-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        #expect(AppSettings.askBeforeEndingGame(in: d), "unset")
        d.set("sometimes", forKey: AppSettings.askBeforeEndingGameKey)
        #expect(AppSettings.askBeforeEndingGame(in: d), "not a Bool")
        d.set(false, forKey: AppSettings.askBeforeEndingGameKey)
        #expect(!AppSettings.askBeforeEndingGame(in: d), "turned off")
    }

    // MARK: Hard Core (spec "Hard Core")

    @Test func theHardCoreSwitchDealsAtOnceOnAFreshGame() {
        let store = makeStore()
        let ui = AppUI()
        ui.requestNewGame(hardCore: true, store: store)
        #expect(ui.pendingNewGame == nil && store.state.isHardCore && store.state.cells.count == 2)
        #expect(store.lastHardCore, "remembered for the next deal")
        store.newGame()
        #expect(store.state.isHardCore, "New Game keeps Hard Core")
        ui.requestNewGame(number: 5, confirmed: true, store: store)
        #expect(store.state.isHardCore && store.state.number == 5, "so does Choose a game")
    }

    @Test func theHardCoreSwitchAsksMidGameAndCancelKeepsTheGame() throws {
        let store = makeStore()
        let ui = AppUI()
        playAMove(store)
        let before = store.state
        ui.requestNewGame(hardCore: true, store: store)
        let ask = try #require(ui.pendingNewGame)
        #expect(ask.kicker == "HARD CORE" && ask.title == "Turn on Hard Core?" && ask.confirm == "Start Hard Core")
        #expect(ask.message.hasPrefix("Two free cells instead of four."))
        #expect(ask.hardCore && ask.changesHardCore)
        #expect(store.state == before && !store.lastHardCore, "nothing dealt or remembered yet")
        ui.pendingNewGame = nil                                    // Cancel
        #expect(!store.state.isHardCore)
    }

    @Test func turningHardCoreOffAsksToo() {
        let store = makeStore(hardCore: true)
        let ui = AppUI()
        playAMove(store)
        ui.requestNewGame(hardCore: false, store: store)
        #expect(ui.pendingNewGame?.title == "Turn off Hard Core?")
        #expect(ui.pendingNewGame?.confirm == "Start New Game")
        #expect(ui.pendingNewGame?.message == "This starts a new game, and the current one will be lost.")
    }

    @Test func resumingAHardCoreGameRemembersIt() {
        let store = makeStore()
        var remembered: [Bool] = []
        store.rememberHardCore = { remembered.append($0) }
        store.resume(from: FreeCellEngine.newGame(number: 5, hardCore: true))
        #expect(store.lastHardCore && remembered == [true])
        store.newGame()
        #expect(store.state.isHardCore)
    }
}

@MainActor @Suite struct Haptics {
    /// Light on a move, success on a win — and nothing when a tap or drop fails.
    @Test func eventsForMovesAndWinsOnly() throws {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C")]))
        #expect(store.feedback == nil)
        _ = store.tap(pile: .tableau(0), index: 9)                   // no such card
        _ = store.drop(source: .tableau(1), index: 0, on: .tableau(0))
        #expect(store.feedback == nil, "nothing on failure")
        #expect(store.tap(pile: .tableau(0), index: 1))
        #expect(store.feedback?.kind == .move)
        let almostWon = try #require(UITestScenario.state(named: "almostWon"))
        store.resume(from: almostWon)
        while let m = FreeCellEngine.nextAutoFinishMove(in: store.state) {
            store.drop(source: m.source, index: m.index, on: m.destination)
        }
        #expect(store.state.isWon && store.feedback?.kind == .win)
    }
}

@Suite struct DropTargets {
    let metrics = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)

    @Test func theNearestPileWins() {
        let s = FreeCellEngine.newGame(number: 617)
        let layout = BoardLayout(state: s, metrics: metrics)
        let col3 = layout.frame(of: .tableau(3))
        #expect(layout.dropTarget(for: CGPoint(x: col3.midX, y: col3.maxY + 40)) == .tableau(3))
        let f2 = layout.slot(.foundation(2))
        #expect(layout.dropTarget(for: CGPoint(x: f2.midX, y: f2.midY)) == .foundation(2))
        let c1 = layout.slot(.cell(1))
        #expect(layout.dropTarget(for: CGPoint(x: c1.midX, y: c1.midY)) == .cell(1))
    }

    /// Hard Core's closed cells take nothing: a drop over one lands on the nearest open pile.
    @Test func closedCellsAreNotTargets() {
        let s = FreeCellEngine.newGame(number: 617, hardCore: true)
        let layout = BoardLayout(state: s, metrics: metrics)
        let closed = layout.slot(.cell(3))
        let target = layout.dropTarget(for: CGPoint(x: closed.midX, y: closed.midY))
        #expect(target != .cell(2) && target != .cell(3) && target != nil)
    }

    /// Released back over its own column, a card lands on its own column — an illegal move, so it
    /// springs back — instead of jumping to whichever other pile is next nearest.
    @Test func releasingOverItsOwnColumnSpringsBack() {
        let s = FreeCellEngine.newGame(number: 617)
        let layout = BoardLayout(state: s, metrics: metrics)
        let own = layout.frame(of: .tableau(5))
        #expect(layout.dropTarget(for: CGPoint(x: own.midX, y: own.midY)) == .tableau(5))
        #expect(!FreeCellEngine.canMove(Move(source: .tableau(5), index: 5, destination: .tableau(5)), in: s))
    }

    @Test func aColumnFrameReachesItsLastCard() {
        let s = FreeCellEngine.newGame(number: 617)
        let layout = BoardLayout(state: s, metrics: metrics)
        let last = layout.placements.last { $0.pile == .tableau(6) }!
        #expect(abs(layout.frame(of: .tableau(6)).maxY - last.frame.maxY) < 0.001, "to within rounding")
        #expect(layout.frame(of: .foundation(0)) == layout.slot(.foundation(0)))
    }
}

@Suite struct DoubleClick {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// Feeds clicks (point, seconds after t0) through one filter; returns which ones acted.
    func acted(_ clicks: [(CGFloat, CGFloat, Double)]) -> [Bool] {
        var f = ClickFilter(interval: 0.5)
        return clicks.map { f.accept(at: CGPoint(x: $0.0, y: $0.1), time: t0.addingTimeInterval($0.2)) }
    }

    @Test func aDoubleOrTripleClickActsOnce() {
        #expect(acted([(10, 10, 0), (12, 11, 0.2), (12, 11, 0.3)]) == [true, false, false])
        #expect(acted([(10, 10, 0), (10, 10, 0.2), (10, 10, 0.9)]) == [true, false, true])
    }

    @Test func separateClicksAllAct() {
        #expect(acted([(10, 10, 0), (200, 10, 0.1), (200, 10, 1.0)]) == [true, true, true])
    }
}

@Suite struct Routing {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    func routes(_ times: [Double], mac: Bool = true) -> [TapRouter.Action] {
        var r = TapRouter(clicks: ClickFilter(interval: 0.5), filtersRepeatClicks: mac)
        return times.map { r.route(at: CGPoint(x: 10, y: 10), time: t0.addingTimeInterval($0)) }
    }

    @Test func aMacDoubleClickOnACardMovesOnce() {
        #expect(routes([0, 0.2]) == [.move, .ignore])
        #expect(routes([0, 0.2], mac: false) == [.move, .move], "iOS taps all act")
    }

    @Test func accessibilityActionsAlwaysAct() {
        var r = TapRouter(clicks: ClickFilter(interval: 0.5), filtersRepeatClicks: true)
        #expect(r.route(at: nil) == .move)
        #expect(r.route(at: nil) == .move)
    }
}

@Suite struct Scenarios {
    @Test(arguments: ["almostWon", "kingToAce"])
    func scenariosAreRealPositions(_ name: String) throws {
        let s = try #require(UITestScenario.state(named: name))
        let all = s.cells.compactMap { $0 } + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
        #expect(all.count == 52 && Set(all.map(\.id)).count == 52)
        #expect(SaveValidation.isResumable(s), "a position a real game could reach")
    }

    @Test func almostWonOffersFinish() throws {
        #expect(FreeCellEngine.canAutoFinish(try #require(UITestScenario.state(named: "almostWon"))))
    }

    /// The profiling position: a whole King→Ace run that lifts as one — and, FreeCell's run limit
    /// being five into the one empty column, springs back.
    @Test func kingToAceIsAThirteenCardRunThatLifts() throws {
        let s = try #require(UITestScenario.state(named: "kingToAce"))
        let run = s.tableau[0]
        #expect(run.map(\.rank) == Array((1...13).reversed()))
        #expect(zip(run, run.dropFirst()).allSatisfy { $0.suit.isRed != $1.suit.isRed })
        #expect(s.tableau[1].isEmpty && FreeCellEngine.canPickUp(from: .tableau(0), index: 0, in: s))
        #expect(!FreeCellEngine.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: s))
        #expect(FreeCellEngine.canMove(Move(source: .tableau(0), index: 8, destination: .tableau(1)), in: s), "five cards do")
    }
}

// MARK: - Restart (spec "Restart")

@MainActor @Suite struct Restarting {
    /// A fresh deal is already the start: nothing to restart, nothing marked.
    @Test func aFreshDealHasNothingToRestart() {
        let store = makeStore()
        let ui = AppUI()
        #expect(!store.canRestart)
        ui.requestRestart(store: store)
        #expect(ui.pendingNewGame == nil && !store.state.isRestarted)
    }

    /// Mid-game it asks; Cancel keeps the game; confirming deals the same game from the start.
    @Test func midGameItAsksThenDealsTheSameGameAgain() throws {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { true }
        let deal = store.state
        playAMove(store); store.tick(); store.tick()
        let played = store.state
        let firstDeal = store.dealID
        ui.requestRestart(store: store)
        let ask = try #require(ui.pendingNewGame)
        #expect(ask.restarts && ask.title == "Restart this game?" && ask.confirm == "Restart" && ask.kicker == "RESTART")
        #expect(store.state == played, "nothing happens until it is confirmed")
        ui.pendingNewGame = nil                                     // Cancel
        ui.requestRestart(store: store)
        ui.confirmPending(store: store)
        var unmarked = store.state
        unmarked.isRestarted = false
        #expect(ui.pendingNewGame == nil && store.state.isRestarted && unmarked == deal)
        #expect(!store.canUndo && store.dealID != firstDeal, "a new playing of the same game")
    }

    @Test func withAskingOffItRestartsAtOnce() {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { false }
        playAMove(store)
        ui.requestRestart(store: store)
        #expect(ui.pendingNewGame == nil && store.state.isRestarted && store.state.moveCount == 0)
    }

    /// The mark lasts through play and further restarts; a new game — or choosing a number again —
    /// clears it.
    @Test func onlyANewGameClearsTheMark() {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { false }
        playAMove(store); ui.requestRestart(store: store)
        playAMove(store); store.undo(); playAMove(store)
        #expect(store.state.isRestarted)
        ui.requestRestart(store: store)
        #expect(store.state.isRestarted)
        ui.requestNewGame(number: 617, confirmed: true, store: store)
        #expect(!store.state.isRestarted && store.state.number == 617, "chosen again: a new game")
    }
}
