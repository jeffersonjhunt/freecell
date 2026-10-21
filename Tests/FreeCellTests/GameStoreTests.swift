import Testing
import FreeCellEngine
@testable import FreeCell

/// A store dealing a fixed sequence of game numbers, so every test is reproducible. Automatic plays
/// settle at once (no 90 ms steps) unless a test asks for them animated.
@MainActor
func makeStore(hardCore: Bool = false, numbers: [Int] = [617, 618, 619, 620], animated: Bool = false) -> GameStore {
    var remaining = numbers
    let store = GameStore(hardCore: hardCore) { remaining.isEmpty ? 1 : remaining.removeFirst() }
    store.animatesAutomaticPlays = animated
    return store
}

/// A store resumed at a hand-built position.
@MainActor
func makeStore(at state: GameState, animated: Bool = false) -> GameStore {
    let store = makeStore(animated: animated)
    store.resume(from: state)
    return store
}

/// A position for store tests; unspecified piles are empty, the other cards nowhere (the store
/// doesn't check that all 52 are present — persistence does).
func position(columns: [[Card]], cells: [Card?] = [], foundations: [[Card]] = [], hardCore: Bool = false) -> GameState {
    let count = FreeCellEngine.cellCount(hardCore: hardCore)
    return GameState(cells: cells + Array(repeating: nil, count: count - cells.count),
                     foundations: foundations + Array(repeating: [], count: 4 - foundations.count),
                     tableau: columns + Array(repeating: [], count: 8 - columns.count),
                     number: 617, isHardCore: hardCore)
}

/// "AS", "10H" or "TH", "KD" → a card.
func card(_ code: String) -> Card {
    let suit: Suit = ["C": .clubs, "D": .diamonds, "H": .hearts, "S": .spades][code.last!]!
    let rankText = String(code.dropLast())
    return Card(suit: suit, rank: ["A": 1, "T": 10, "J": 11, "Q": 12, "K": 13][rankText] ?? Int(rankText)!)
}

func cards(_ codes: String) -> [Card] { codes.split(separator: " ").map { card(String($0)) } }

/// A full suit's foundation, ace to `rank`.
func foundation(_ suit: Suit, upTo rank: Int) -> [Card] { (1...rank).map { Card(suit: suit, rank: $0) } }

/// The moves a random player picks from: every legal move except into a free cell — unless that is
/// all there is. (Random play that uses cells freely fills them and gets stuck within a few moves.)
func randomPlayerMoves(_ s: GameState) -> [Move] {
    let all = legalMoves(s)
    let withoutCells = all.filter { if case .cell = $0.destination { false } else { true } }
    return withoutCells.isEmpty ? all : withoutCells
}

/// Every move the rules allow.
func legalMoves(_ s: GameState) -> [Move] {
    var sources: [(PileID, Int)] = s.cells.indices.map { (.cell($0), 0) }
    for t in 0..<8 { for i in s.tableau[t].indices { sources.append((.tableau(t), i)) } }
    let destinations: [PileID] = s.cells.indices.map { .cell($0) } + (0..<4).map { .foundation($0) }
        + (0..<8).map { .tableau($0) }
    return sources.flatMap { src, i in destinations.map { Move(source: src, index: i, destination: $0) } }
        .filter { FreeCellEngine.canMove($0, in: s) }
}

func cardsHome(_ s: GameState) -> Int { s.foundations.reduce(0) { $0 + $1.count } }

@MainActor @Suite struct Undo {
    /// Acceptance: undo from any point returns the exact previous board and move count over 100
    /// random moves from a fixed game — automatic plays included — the undo count rising by one each
    /// time.
    @Test func hundredRandomMovesUndoExactly() {
        // Game 5: its aces come free within a random walk (617's sit 4–8 cards deep and never do).
        let store = makeStore(numbers: [5])
        var rng = SplitMix64(seed: 7)
        var history = [store.state]
        var automatic = 0
        while history.count <= 100 {
            let before = store.state
            let moves = randomPlayerMoves(before)
            guard !moves.isEmpty else { break }
            // Half the time, steer toward a move that sets off an automatic play (random moves alone
            // almost never uncover an ace), so the walk undoes through them too.
            let setsOff = moves.filter { m in
                var after = before
                FreeCellEngine.apply(m, to: &after)
                return FreeCellEngine.nextSafePlay(in: after) != nil
            }
            let pool = !setsOff.isEmpty && rng.next() % 2 == 0 ? setsOff : moves
            let m = pool[Int(rng.next() % UInt64(pool.count))]
            #expect(store.drop(source: m.source, index: m.index, on: m.destination))
            let homeByHand = if case .foundation = m.destination { 1 } else { 0 }
            if cardsHome(store.state) > cardsHome(before) + homeByHand { automatic += 1 }
            history.append(store.state)
        }
        #expect(history.count == 101 && automatic > 0, "the walk must set off automatic plays (\(automatic))")
        for (n, var expected) in history.dropLast().reversed().enumerated() {
            store.undo()
            expected.undos = n + 1
            #expect(store.state == expected)
        }
        #expect(!store.canUndo)
    }

    /// One Undo takes back a move and the automatic plays it set off.
    @Test func aMoveAndItsAutomaticPlaysAreOneUndo() {
        let start = position(columns: [cards("AS 5H"), cards("6C"), cards("KD")])
        let store = makeStore(at: start)
        #expect(store.drop(source: .tableau(0), index: 1, on: .tableau(1)))
        #expect(store.state.foundations.contains(cards("AS")) && store.state.tableau[0].isEmpty)
        #expect(store.state.moveCount == 1, "the automatic play costs no move")
        store.undo()
        var expected = start
        expected.undos = 1
        #expect(store.state == expected)
    }

    @Test func automaticPlaysCanBeTurnedOff() {
        let store = makeStore(at: position(columns: [cards("AS 5H"), cards("6C")]))
        store.playsCardsHome = { false }
        #expect(store.drop(source: .tableau(0), index: 1, on: .tableau(1)))
        #expect(store.state.tableau[0] == cards("AS") && store.state.foundations.allSatisfy(\.isEmpty))
    }

    /// Animated, the automatic plays wait their turn — but a new move never races them: they all
    /// land first.
    @Test func aNewMoveSettlesWaitingAutomaticPlaysFirst() {
        let store = makeStore(at: position(columns: [cards("AS 5H"), cards("6C"), cards("KD 9D")]), animated: true)
        #expect(store.drop(source: .tableau(0), index: 1, on: .tableau(1)))
        #expect(store.state.tableau[0] == cards("AS"), "still waiting its 90 ms")
        #expect(store.tap(pile: .tableau(2), index: 1))                        // 9♦ to a free cell
        #expect(store.state.foundations.contains(cards("AS")) && store.state.cells[0] == card("9D"))
    }

    @Test func undoKeepsTheClockAndCountsItself() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C")]))
        #expect(store.drop(source: .tableau(0), index: 1, on: .tableau(1)))
        store.tick(); store.tick()
        let before = store.state
        store.undo()
        #expect(store.state.elapsed == before.elapsed, "time isn't taken back")
        #expect(store.state.undos == 1 && store.state.moveCount == 0)
    }

    @Test func undoStackIsCappedAtThreeHundred() {
        let store = makeStore(at: position(columns: [cards("KH")]))
        for i in 0..<350 {                                                    // into a cell and back
            if i % 2 == 0 {
                #expect(store.drop(source: .tableau(0), index: 0, on: .cell(0)))
            } else {
                #expect(store.drop(source: .cell(0), index: 0, on: .tableau(0)))
            }
        }
        #expect(store.undoStack.count == GameStore.undoLimit)
        var oldestKept = store.undoStack.first
        for _ in 0..<GameStore.undoLimit { store.undo() }
        oldestKept?.undos = GameStore.undoLimit
        #expect(store.state == oldestKept)
        #expect(!store.canUndo)
    }

    @Test func aNewDealClearsUndo() {
        let store = makeStore()
        let move = legalMoves(store.state).first!
        #expect(store.drop(source: move.source, index: move.index, on: move.destination))
        #expect(store.canUndo)
        store.newGame()
        #expect(!store.canUndo && store.state.number == 618 && store.state.moveCount == 0)
    }
}

@MainActor @Suite struct Winning {
    static var nearlyWon: GameState {
        var s = position(columns: [cards("KC")], foundations: Suit.allCases.map { foundation($0, upTo: 13) })
        s.foundations[0].removeLast()                                         // the K♣ is in column 1
        return s
    }

    /// A won game cannot be un-won: undo is refused.
    @Test func undoDoesNothingOnceWon() {
        let store = makeStore(at: Self.nearlyWon)
        #expect(store.tap(pile: .tableau(0), index: 0))
        #expect(store.state.isWon && !store.canUndo)
        let won = store.state
        store.undo()
        #expect(store.state == won)
    }

    /// Automatic plays can finish a game: moving the Q♦ off the K♦ sends the Q♦, K♦ and K♣ home
    /// by themselves — and the win is reported once.
    @Test func automaticPlaysCanWinAndTheWinIsReportedOnce() {
        var s = position(columns: [cards("KC"), cards("KD QD")], foundations: Suit.allCases.map { foundation($0, upTo: 13) })
        s.foundations[0].removeLast()                                         // K♣ in column 1
        s.foundations[1].removeLast(2)                                        // Q♦ K♦ in column 2
        let store = makeStore(at: s)
        var wins = 0
        store.onWin = { _ in wins += 1 }
        #expect(store.drop(source: .tableau(1), index: 1, on: .cell(0)))
        #expect(store.state.isWon && wins == 1 && store.state.moveCount == 1)
    }
}

@MainActor @Suite struct Intents {
    @Test func anOutOfRangeNumberIsClampedNotACrash() {
        let store = makeStore()
        store.newGame(number: 0)
        #expect(store.state.number == 1)
        store.newGame(number: 2_000_000)
        #expect(store.state.number == 1_000_000)
    }

    @Test func aTapWithNowhereToGoChangesNothing() {
        let store = makeStore()
        let before = store.state
        #expect(!store.tap(pile: .tableau(0), index: 9))       // no such card
        #expect(!store.tap(pile: .foundation(0), index: 0))
        #expect(store.state == before && !store.canUndo)
    }

    @Test func anIllegalDropSpringsBackUnchanged() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6D")]))
        let before = store.state
        #expect(!store.drop(source: .tableau(0), index: 1, on: .tableau(1)))   // red on red
        #expect(store.state == before && !store.canUndo)
    }

    @Test func aLegalTapMovesAndIsOneUndoStep() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C")]))
        #expect(store.tap(pile: .tableau(0), index: 1))
        #expect(store.state.tableau[1] == cards("6C 5H"))
        #expect(store.state.moveCount == 1 && store.undoStack.count == 1)
    }
}

@MainActor @Suite struct Clock {
    @Test func theClockRunsOnlyWhileStartedUnwonAndActive() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C")]))
        store.tick()
        #expect(store.state.elapsed == 0, "not started before the first move")
        #expect(store.tap(pile: .tableau(0), index: 1))
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
