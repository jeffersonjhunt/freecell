import CoreGraphics
import Foundation
import Testing
import SolitaireEngine
@testable import Solitaire

@MainActor @Suite struct Dragging {
    @Test func onlyPickableCardsStartADrag() {
        let store = makeStore()
        #expect(!store.beginDrag(pile: .tableau(6), index: 0), "face down")
        #expect(store.pendingDrag == nil)
        #expect(!store.beginDrag(pile: .stock, index: 23))
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        #expect(store.pendingDrag == GameStore.PendingDrag(source: .tableau(6), index: 6))
        store.cancelDrag()
        #expect(store.pendingDrag == nil)
    }

    /// Undo, a draw or any other change that moves cards ends a drag in progress (else the drag
    /// stayed pending and no other card could be dragged); the clock's tick does not.
    @Test func changesThatMoveCardsEndADrag() throws {
        let store = makeStore()
        let move = try #require(legalMoves(store.state).first)
        store.drop(source: move.source, index: move.index, on: move.destination)
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        store.tick()
        #expect(store.pendingDrag != nil, "a tick moves nothing")
        store.undo()
        #expect(store.pendingDrag == nil, "undo ends it")
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        store.tapStock()
        #expect(store.pendingDrag == nil, "a draw ends it")
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        store.resume(from: store.state)
        #expect(store.pendingDrag != nil, "resuming the same position moves nothing")
        store.newGame()
        #expect(store.pendingDrag == nil)
    }

    @Test func aDropEndsTheDragLegalOrNot() throws {
        let store = makeStore()
        let move = try #require(legalMoves(store.state).first)
        #expect(store.beginDrag(pile: move.source, index: move.index))
        #expect(store.drop(source: move.source, index: move.index, on: move.destination))
        #expect(store.pendingDrag == nil)
        #expect(store.beginDrag(pile: .tableau(0), index: 0))
        let before = store.state
        #expect(!store.drop(source: .tableau(0), index: 0, on: .tableau(0)))
        #expect(store.pendingDrag == nil && store.state == before)
    }
}

/// Spec "New games and the draw mode": New Game and the draw chip deal at once unless a game in
/// progress would be lost; then they only ask.
@MainActor @Suite struct NewGamesAndTheDrawMode {
    @Test func aFreshDealIsReplacedAtOnce() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        #expect(!store.isInProgress, "no move made yet")
        ui.requestNewGame(drawCount: 3, store: store)               // the chip
        #expect(ui.pendingNewGame == nil && store.state.drawCount == 3 && store.lastDrawCount == 3)
        let seed = store.state.seed
        ui.requestNewGame(store: store)                             // New Game
        #expect(ui.pendingNewGame == nil && store.state.seed != seed && store.state.drawCount == 3,
                "a new deal in the same mode")
    }

    @Test func aGameInProgressIsAskedAboutAndKeptUntilConfirmed() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        store.tapStock()                                            // a draw counts as a move
        #expect(store.isInProgress)
        let before = store.state
        ui.requestNewGame(drawCount: 3, store: store)
        #expect(ui.pendingNewGame == NewGameRequest(drawCount: 3, switching: true))
        #expect(store.state == before && store.lastDrawCount == 1, "nothing dealt or remembered yet")
        #expect(ui.pendingNewGame?.title == "Switch to Draw 3?")
        #expect(ui.pendingNewGame?.confirm == "Start New Game")
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame == NewGameRequest(drawCount: 1, switching: false))
        #expect(ui.pendingNewGame?.title == "Start a new game?" && ui.pendingNewGame?.message == "This one will be lost.")
        #expect(store.state == before)
    }

    @Test func aWonGameIsReplacedAtOnce() {
        let store = makeStore(drawCount: 3)
        let ui = AppUI()
        let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]
        store.resume(from: GameState(stock: [], waste: [],
                                     foundations: suits.map { s in (1...13).map { Card(suit: s, rank: $0, isFaceUp: true) } },
                                     tableau: Array(repeating: [], count: 7), drawCount: 3, moveCount: 120, isWon: true))
        #expect(!store.isInProgress, "won: nothing to lose")
        ui.requestNewGame(drawCount: 1, store: store)
        #expect(ui.pendingNewGame == nil && store.state.drawCount == 1 && !store.state.isWon)
    }

    /// The resumed game's mode is the last deal's: New Game continues in it.
    @Test func resumingRemembersTheGamesMode() {
        let store = makeStore(drawCount: 1)
        var saved = makeStore(drawCount: 3).state
        saved.moveCount = 5
        store.resume(from: saved)
        #expect(store.lastDrawCount == 3)
        store.newGame()
        #expect(store.state.drawCount == 3)
    }

    /// Asking stops auto-finish: no card flies home behind the question, and the game cannot be
    /// won there. Finish is still offered afterwards.
    @Test func askingStopsAutoFinish() async {
        let store = makeStore()
        var s = UITestScenario.state(named: "almostWon")!
        s.moveCount = 40
        store.resume(from: s)
        store.autoFinish()
        #expect(store.isAutoFinishing)
        let ui = AppUI()
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame != nil && !store.isAutoFinishing)
        let home = store.state.foundations.map(\.count)
        try? await Task.sleep(for: GameStore.autoFinishStep * 4)
        #expect(store.state.foundations.map(\.count) == home && !store.state.isWon, "nothing more went home")
        #expect(store.canAutoFinish, "Finish is offered again")
    }

    /// Settings ▸ Ask before ending a game off: a game in progress is replaced at once too.
    @Test func withAskingOffAGameInProgressIsReplacedAtOnce() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        ui.asksBeforeEndingGame = { false }
        store.tapStock()
        #expect(store.isInProgress)
        ui.requestNewGame(drawCount: 3, store: store)
        #expect(ui.pendingNewGame == nil && store.state.drawCount == 3 && store.state.moveCount == 0)
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
        let store = makeStore(drawCount: 3)
        let ui = AppUI()
        ui.requestNewGame(hardCore: true, store: store)
        #expect(ui.pendingNewGame == nil && store.state.isHardCore && store.state.drawCount == 3)
        #expect(store.lastHardCore, "remembered for the next deal")
        store.newGame()
        #expect(store.state.isHardCore, "New Game keeps Hard Core")
        ui.requestNewGame(drawCount: 1, store: store)
        #expect(store.state.isHardCore && store.state.drawCount == 1, "so does the draw chip")
    }

    @Test func theHardCoreSwitchAsksMidGameAndCancelKeepsTheGame() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        store.tapStock()
        let before = store.state
        ui.requestNewGame(hardCore: true, store: store)
        let ask = try! #require(ui.pendingNewGame)
        #expect(ask.kicker == "HARD CORE" && ask.title == "Turn on Hard Core?" && ask.confirm == "Start Hard Core")
        #expect(ask.message.hasPrefix("Draw 1 gets one pass through the deck, Draw 3 gets three."))
        #expect(ask.hardCore && ask.changesHardCore && !ask.switching)
        #expect(store.state == before && !store.lastHardCore, "nothing dealt or remembered yet")
        ui.pendingNewGame = nil                                    // Cancel
        #expect(!store.state.isHardCore)
    }

    @Test func turningHardCoreOffAsksToo() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        store.newGame(drawCount: 1, hardCore: true)
        store.tapStock()
        ui.requestNewGame(hardCore: false, store: store)
        #expect(ui.pendingNewGame?.title == "Turn off Hard Core?")
        #expect(ui.pendingNewGame?.confirm == "Start New Game")
        #expect(ui.pendingNewGame?.message == "This starts a new game, and the current one will be lost.")
    }

    @Test func resumingAHardCoreGameRemembersIt() {
        let store = makeStore(drawCount: 1)
        var remembered: [Bool] = []
        store.rememberHardCore = { remembered.append($0) }
        store.resume(from: SolitaireEngine.newGame(drawCount: 3, seed: 5, hardCore: true))
        #expect(store.lastHardCore && remembered == [true])
        store.newGame()
        #expect(store.state.isHardCore && store.state.drawCount == 3)
    }

    @Test func anInvalidCountBecomesDrawOne() {
        let store = makeStore(drawCount: 3)
        AppUI().requestNewGame(drawCount: 7, store: store)
        #expect(store.state.drawCount == 1)
    }
}

@MainActor @Suite struct Haptics {
    /// Light on a move, soft on a draw, success on a win — and nothing when a tap or drop fails.
    @Test func eventsForMovesDrawsAndWinsOnly() throws {
        let store = makeStore()
        #expect(store.feedback == nil)
        _ = store.tap(pile: .tableau(0), index: 5)                   // no such card
        _ = store.drop(source: .tableau(6), index: 0, on: .tableau(0))
        #expect(store.feedback == nil, "nothing on failure")
        store.tapStock()
        #expect(store.feedback?.kind == .draw)
        let move = try #require(legalMoves(store.state).first)
        store.drop(source: move.source, index: move.index, on: move.destination)
        #expect(store.feedback?.kind == .move)
        let first = store.feedback
        store.tapStock()
        store.tapStock()
        #expect(store.feedback?.kind == .draw && store.feedback != first)
        let almostWon = try #require(UITestScenario.state(named: "almostWon"))
        store.resume(from: almostWon)
        while let m = SolitaireEngine.nextAutoFinishMove(in: store.state) {
            store.drop(source: m.source, index: m.index, on: m.destination)
        }
        #expect(store.state.isWon && store.feedback?.kind == .win)
    }
}

@Suite struct DropTargets {
    let metrics = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)

    @Test func theNearestPileWins() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let col3 = layout.frame(of: .tableau(3))
        #expect(layout.dropTarget(for: CGPoint(x: col3.midX, y: col3.maxY + 40)) == .tableau(3))
        let f2 = layout.slot(.foundation(2))
        #expect(layout.dropTarget(for: CGPoint(x: f2.midX, y: f2.midY)) == .foundation(2))
    }

    /// Released back over its own column, a card lands on its own column — an illegal move, so it
    /// springs back — instead of jumping to whichever other pile is next nearest.
    @Test func releasingOverItsOwnColumnSpringsBack() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let own = layout.frame(of: .tableau(5))
        let target = layout.dropTarget(for: CGPoint(x: own.midX, y: own.midY))
        #expect(target == .tableau(5))
        #expect(!SolitaireEngine.canMove(Move(source: .tableau(5), index: 5, destination: .tableau(5)), in: s))
    }

    @Test func aColumnFrameReachesItsLastCard() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let last = layout.placements.last { $0.pile == .tableau(6) }!
        #expect(layout.frame(of: .tableau(6)).maxY == last.frame.maxY)
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
        // the first click acts; the second (0.2 s later, 2 pt away) and a third are swallowed
        #expect(acted([(10, 10, 0), (12, 11, 0.2), (12, 11, 0.3)]) == [true, false, false])
        // …until the clicks pause for longer than the interval
        #expect(acted([(10, 10, 0), (10, 10, 0.2), (10, 10, 0.9)]) == [true, false, true])
    }

    @Test func separateClicksAllAct() {
        // somewhere else, then too late to be a double-click
        #expect(acted([(10, 10, 0), (200, 10, 0.1), (200, 10, 1.0)]) == [true, true, true])
    }
}

@Suite struct Routing {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    func routes(_ taps: [(PileID, Double)], mac: Bool = true) -> [TapRouter.Action] {
        var r = TapRouter(clicks: ClickFilter(interval: 0.5), filtersRepeatClicks: mac)
        return taps.map { r.route($0.0, at: CGPoint(x: 10, y: 10), time: t0.addingTimeInterval($0.1)) }
    }

    /// Every click on the stock draws, however fast — the double-click filter is for card moves.
    @Test func fastClicksOnTheStockAllDraw() {
        #expect(routes([(.stock, 0), (.stock, 0.1), (.stock, 0.2)]) == [.draw, .draw, .draw])
    }

    @Test func aMacDoubleClickOnACardMovesOnce() {
        #expect(routes([(.tableau(2), 0), (.tableau(2), 0.2)]) == [.move, .ignore])
        #expect(routes([(.tableau(2), 0), (.tableau(2), 0.2)], mac: false) == [.move, .move], "iOS taps all act")
    }

    @Test func accessibilityActionsAlwaysAct() {
        var r = TapRouter(clicks: ClickFilter(interval: 0.5), filtersRepeatClicks: true)
        #expect(r.route(.waste, at: nil) == .move)
        #expect(r.route(.waste, at: nil) == .move)
    }
}

@Suite struct Scenarios {
    @Test(arguments: ["almostWon", "kingAlone", "kingToAce"])
    func scenariosAreRealPositions(_ name: String) throws {
        let s = try #require(UITestScenario.state(named: name))
        let cards = s.stock + s.waste + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
        #expect(cards.count == 52 && Set(cards.map(\.id)).count == 52)
        #expect(s.tableau.allSatisfy { $0.isEmpty || $0.last!.isFaceUp })
    }

    @Test func scenariosSetUpWhatTheUITestsNeed() throws {
        let won = try #require(UITestScenario.state(named: "almostWon"))
        #expect(SolitaireEngine.canAutoFinish(won))
        let king = try #require(UITestScenario.state(named: "kingAlone"))
        #expect(king.tableau[0] == [Card(suit: .hearts, rank: 13, isFaceUp: true)] && king.tableau[1].isEmpty)
        #expect(SolitaireEngine.autoDestination(for: .tableau(0), index: 0, in: king) == nil)
        #expect(SolitaireEngine.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: king))
    }

    /// The profiling position: a whole King→Ace run that can be picked up and moved as one.
    @Test func kingToAceIsAThirteenCardRunThatMovesWhole() throws {
        let s = try #require(UITestScenario.state(named: "kingToAce"))
        let run = s.tableau[0]
        #expect(run.map(\.rank) == Array((1...13).reversed()) && run.allSatisfy(\.isFaceUp))
        #expect(zip(run, run.dropFirst()).allSatisfy { $0.suit.isRed != $1.suit.isRed })
        #expect(s.tableau[1].isEmpty)
        #expect(SaveValidation.isResumable(s), "a position a real game could reach")
        #expect(SolitaireEngine.canPickUp(from: .tableau(0), index: 0, in: s))
        #expect(SolitaireEngine.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: s))
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

    /// Mid-game it asks; Cancel keeps the game; confirming deals the same cards from the start.
    @Test func midGameItAsksThenDealsTheSameGameAgain() throws {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { true }
        let deal = store.state
        store.tapStock(); store.tick(); store.tick()
        let move = try #require(legalMoves(store.state).first)
        store.drop(source: move.source, index: move.index, on: move.destination)
        let played = store.state
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
        #expect(!store.canUndo && store.score == 0)
    }

    @Test func withAskingOffItRestartsAtOnce() {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { false }
        store.tapStock()
        ui.requestRestart(store: store)
        #expect(ui.pendingNewGame == nil && store.state.isRestarted && store.state.moveCount == 0)
    }

    /// The mark lasts through play and further restarts; a new game clears it.
    @Test func onlyANewGameClearsTheMark() {
        let store = makeStore()
        let ui = AppUI()
        ui.asksBeforeEndingGame = { false }
        store.tapStock(); ui.requestRestart(store: store)
        store.tapStock(); store.undo(); store.tapStock()
        #expect(store.state.isRestarted && store.score == 0)
        ui.requestRestart(store: store)
        #expect(store.state.isRestarted)
        ui.requestNewGame(store: store)
        #expect(!store.state.isRestarted && store.state.seed != 42)
    }
}
