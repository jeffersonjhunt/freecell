import Testing
import SolitaireEngine
@testable import Solitaire

/// A store dealing a fixed sequence of seeds, so every test is reproducible.
@MainActor
func makeStore(drawCount: Int = 1, seeds: [UInt64] = [42, 43, 44, 45]) -> GameStore {
    var remaining = seeds
    return GameStore(drawCount: drawCount) { remaining.isEmpty ? 0 : remaining.removeFirst() }
}

/// Every move the rules allow (excluding the stock tap).
func legalMoves(_ s: GameState) -> [Move] {
    var sources: [(PileID, Int)] = []
    if !s.waste.isEmpty { sources.append((.waste, s.waste.count - 1)) }
    for f in 0..<4 where !s.foundations[f].isEmpty { sources.append((.foundation(f), s.foundations[f].count - 1)) }
    for t in 0..<7 { for i in s.tableau[t].indices { sources.append((.tableau(t), i)) } }
    let destinations: [PileID] = (0..<4).map { .foundation($0) } + (0..<7).map { .tableau($0) }
    return sources.flatMap { src, i in destinations.map { Move(source: src, index: i, destination: $0) } }
        .filter { SolitaireEngine.canMove($0, in: s) }
}

@MainActor @Suite struct Undo {
    /// Acceptance: undo from any point returns the exact previous board, moves and passes, including
    /// face-up flips and redeals, for 100 random moves from a fixed seed — the undo count rising by
    /// one each time (spec "Scoring").
    @Test func hundredRandomMovesUndoExactly() {
        let store = makeStore()
        var rng = SplitMix64(seed: 7)
        var history = [store.state]
        var flips = 0, redeals = 0
        while history.count <= 100 {
            let before = store.state
            let moves = legalMoves(before)
            if !moves.isEmpty && rng.next() % 3 != 0 {
                let m = moves[Int(rng.next() % UInt64(moves.count))]
                #expect(store.drop(source: m.source, index: m.index, on: m.destination))
                if case .tableau(let t) = m.source, m.index > 0, !before.tableau[t][m.index - 1].isFaceUp { flips += 1 }
            } else {
                if before.stock.isEmpty && !before.waste.isEmpty { redeals += 1 }
                store.tapStock()
                if store.state == before { continue }        // nothing to draw: not a step
            }
            history.append(store.state)
        }
        #expect(flips > 0 && redeals > 0, "the walk must include flips (\(flips)) and redeals (\(redeals))")
        for (n, var expected) in history.dropLast().reversed().enumerated() {
            store.undo()
            expected.undos = n + 1
            #expect(store.state == expected)
        }
        #expect(!store.canUndo)
    }

    /// Undo keeps the clock's time and counts itself; the undone move's points go with it.
    @Test func undoKeepsTheClockAndCountsItself() {
        let store = makeStore()
        store.tapStock()
        store.tick(); store.tick()
        let before = store.state
        store.undo()
        #expect(store.state.elapsed == before.elapsed, "time isn't taken back")
        #expect(store.state.undos == 1 && store.score == 0, "−3 on nothing is still 0")
        store.tapStock(); store.undo()
        #expect(store.state.undos == 2, "and every undo counts")
    }

    /// Undo takes a redeal back, pass count included.
    @Test func undoTakesARedealBack() {
        let store = makeStore()
        while !store.state.stock.isEmpty { store.tapStock() }
        store.tapStock()                                            // redeal
        #expect(store.state.redeals == 1)
        store.undo()
        #expect(store.state.redeals == 0 && store.state.passes == 1 && store.state.stock.isEmpty)
    }

    @Test func undoStackIsCappedAtThreeHundred() {
        let store = makeStore()
        for _ in 0..<350 { store.tapStock() }
        #expect(store.undoStack.count == GameStore.undoLimit)
        var oldestKept = store.undoStack.first
        for _ in 0..<GameStore.undoLimit { store.undo() }
        oldestKept?.undos = GameStore.undoLimit                    // every undo is counted (spec "Scoring")
        #expect(store.state == oldestKept)
        #expect(!store.canUndo)
    }

    @Test func aNewDealClearsUndo() {
        let store = makeStore()
        store.tapStock()
        #expect(store.canUndo)
        store.newGame(drawCount: 3)
        #expect(!store.canUndo && store.state.drawCount == 3 && store.state.seed == 43)
    }
}

@MainActor @Suite struct Winning {
    /// A won game cannot be un-won: undo is refused (and a second win would lose its sheet).
    @Test func undoDoesNothingOnceWon() {
        let store = makeStore()
        var s = store.state
        s.stock = []; s.waste = []
        s.foundations = [Suit.spades, .hearts, .diamonds, .clubs].map { suit in
            (1...13).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        let king = s.foundations[3].removeLast()
        s.tableau = [[king], [], [], [], [], [], []]
        store.resume(from: s)
        #expect(store.tap(pile: .tableau(0), index: 0))
        #expect(store.state.isWon && !store.canUndo)
        let won = store.state
        store.undo()
        #expect(store.state == won)
    }
}

@MainActor @Suite struct Intents {
    @Test func anInvalidDrawCountIsClampedNotACrash() {
        #expect(makeStore(drawCount: 7).state.drawCount == 1)
        let store = makeStore()
        store.newGame(drawCount: 0)
        #expect(store.state.drawCount == 1)
        store.newGame(drawCount: 3)
        #expect(store.state.drawCount == 3)
    }

    @Test func aTapWithNowhereToGoChangesNothing() {
        let store = makeStore()
        let before = store.state
        #expect(!store.tap(pile: .tableau(0), index: 5))       // no such card
        #expect(!store.tap(pile: .stock, index: 0))
        #expect(store.state == before && !store.canUndo)
    }

    @Test func anIllegalDropSpringsBackUnchanged() {
        let store = makeStore()
        let before = store.state
        #expect(!store.drop(source: .tableau(6), index: 0, on: .tableau(0)))   // a face-down card
        #expect(store.state == before && !store.canUndo)
    }

    @Test func aLegalTapMovesAndIsOneUndoStep() throws {
        let store = makeStore()
        let move = try #require(legalMoves(store.state).first { SolitaireEngine.autoDestination(for: $0.source, index: $0.index, in: store.state) != nil })
        #expect(store.tap(pile: move.source, index: move.index))
        #expect(store.state.moveCount == 1 && store.undoStack.count == 1)
    }
}

@MainActor @Suite struct Clock {
    @Test func theClockRunsOnlyWhileStartedUnwonAndActive() {
        let store = makeStore()
        store.tick()
        #expect(store.state.elapsed == 0, "not started before the first move")
        store.tapStock()
        store.tick(); store.tick()
        #expect(store.state.elapsed == 2)
        store.isActive = false
        store.tick()
        #expect(store.state.elapsed == 2, "paused in the background")
        store.isActive = true
        store.tick()
        #expect(store.state.elapsed == 3)
    }
}
