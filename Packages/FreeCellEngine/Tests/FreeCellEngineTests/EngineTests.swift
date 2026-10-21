import Foundation
import Testing
@testable import FreeCellEngine

// MARK: - The deal (spec "Game rules" › Deal)

@Suite struct Dealing {
    /// The deal as the published layouts write it: rows across the eight columns.
    func rows(_ number: Int) -> [String] {
        let columns = E.deal(number: number)
        return (0..<7).map { row in columns.compactMap { $0.indices.contains(row) ? name($0[row]) : nil }.joined(separator: " ") }
    }

    @Test func game1IsMicrosoftsGame1() {
        #expect(rows(1) == ["JD 2D 9H JC 5D 7H 7C 5H", "KD KC 9S 5S AD QC KH 3H", "2S KS 9D QD JS AS AH 3C",
                            "4C 5C TS QH 4H AC 4D 7S", "3S TD 4S TH 8H 2C JH 7D", "6D 8S 8D QS 6C 3D 8C TC",
                            "6S 9C 2H 6H"])
    }

    @Test func game617IsMicrosoftsGame617() {
        #expect(rows(617) == ["7D AD 5C 3S 5S 8C 2D AH", "TD 7S QD AC 6D 8H AS KH", "TH QC 3H 9D 6S 8D 3D TC",
                              "KD 5H 9S 3C 8S 7H 4D JS", "4C QS 9C 9H 7C 6H 2C 2S", "4S TS 2H 5D JC 6C JH QH",
                              "JD KS KC 4H"])
    }

    @Test(arguments: [1, 2, 617, 11982, 32000, 500_000, 1_000_000])
    func everyDealHas52CardsInColumnsOfSevenAndSix(number: Int) {
        let s = E.newGame(number: number)
        #expect(s.tableau.map(\.count) == [7, 7, 7, 7, 6, 6, 6, 6])
        #expect(Set(allCards(s)).count == 52)
        #expect(s.cells == [nil, nil, nil, nil] && s.foundations.allSatisfy(\.isEmpty))
        #expect(s.number == number && s.moveCount == 0 && !s.isWon)
    }

    @Test func hardCoreHasTwoFreeCells() {
        let s = E.newGame(number: 5, hardCore: true)
        #expect(s.cells.count == 2 && s.isHardCore)
        #expect(s.tableau == E.newGame(number: 5).tableau, "the same deal either way")
    }

    @Test func newGameNeverDealsAnUnwinnableNumber() {
        #expect(E.unwinnable.count == 8 && E.unwinnable.contains(11982))
        var g = SeededGenerator(state: 1)
        for _ in 0..<5000 {
            let n = E.randomNumber(using: &g)
            #expect(E.numbers.contains(n) && !E.unwinnable.contains(n))
        }
    }

    @Test func restartDealsTheSameNumberAgainMarked() {
        var s = E.newGame(number: 617, hardCore: true)
        s.moveCount = 12; s.elapsed = 40; s.undos = 2
        s.cells[0] = s.tableau[0].removeLast()
        let again = E.restart(s)
        #expect(again.isRestarted && again.number == 617 && again.isHardCore)
        #expect(again.tableau == E.deal(number: 617) && again.moveCount == 0 && again.elapsed == 0 && again.undos == 0)
    }
}

// MARK: - Moves (spec "Game rules" › Moves)

@Suite struct SingleCards {
    @Test func foundationsBuildUpBySuitFromTheAce() {
        let s = board(columns: [cards("AS"), cards("2S"), cards("2H")], foundations: [])
        #expect(E.canMove(Move(source: .tableau(0), index: 0, destination: .foundation(0)), in: s))
        #expect(!E.canMove(Move(source: .tableau(1), index: 0, destination: .foundation(0)), in: s), "no ace yet")
        let t = board(columns: [cards("2S"), cards("2H"), cards("3S")], foundations: [foundation(.spades, upTo: 1)])
        #expect(E.canMove(Move(source: .tableau(0), index: 0, destination: .foundation(0)), in: t))
        #expect(!E.canMove(Move(source: .tableau(1), index: 0, destination: .foundation(0)), in: t), "wrong suit")
        #expect(!E.canMove(Move(source: .tableau(2), index: 0, destination: .foundation(0)), in: t), "skips a rank")
    }

    @Test func aCardOnAFoundationNeverMoves() {
        let s = board(columns: [cards("3H")], foundations: [foundation(.spades, upTo: 2)])
        #expect(!E.canMove(Move(source: .foundation(0), index: 1, destination: .tableau(0)), in: s))
        #expect(!E.canMove(Move(source: .foundation(0), index: 1, destination: .tableau(1)), in: s))
        #expect(!E.canPickUp(from: .foundation(0), index: 1, in: s))
        #expect(E.autoDestination(for: .foundation(0), index: 1, in: s) == nil)
    }

    @Test func columnsBuildDownInAlternatingColours() {
        let s = board(columns: [cards("7H"), cards("8S"), cards("8D"), cards("9S"), [], cards("3C")])
        #expect(E.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: s))
        #expect(!E.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(2)), in: s), "same colour")
        #expect(!E.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(3)), in: s), "two ranks apart")
        #expect(E.canMove(Move(source: .tableau(5), index: 0, destination: .tableau(4)), in: s), "any card to an empty column")
    }

    @Test func freeCellsHoldOneCardFromAColumn() {
        let s = board(columns: [cards("9C 7H"), cards("8S")], cells: [c("KD")])
        #expect(E.canMove(Move(source: .tableau(0), index: 1, destination: .cell(1)), in: s))
        #expect(!E.canMove(Move(source: .tableau(0), index: 1, destination: .cell(0)), in: s), "occupied")
        #expect(!E.canMove(Move(source: .tableau(0), index: 0, destination: .cell(1)), in: s), "not the last card")
        #expect(!E.canMove(Move(source: .cell(0), index: 0, destination: .cell(1)), in: s), "never cell to cell")
        let fromCell = board(columns: [cards("8S"), []], cells: [c("7H")])
        #expect(E.canMove(Move(source: .cell(0), index: 0, destination: .tableau(0)), in: fromCell))
        #expect(E.canMove(Move(source: .cell(0), index: 0, destination: .tableau(1)), in: fromCell))
    }

    @Test func hardCoreHasOnlyTwoCells() {
        let s = board(columns: [cards("9C 7H 4S")], hardCore: true)
        #expect(E.canMove(Move(source: .tableau(0), index: 2, destination: .cell(1)), in: s))
        #expect(!E.canMove(Move(source: .tableau(0), index: 2, destination: .cell(2)), in: s), "there is no third cell")
    }

    @Test func aCardUnderAnOutOfOrderCardCantBeLifted() {
        let s = board(columns: [cards("8S 3H"), cards("9D")])
        #expect(!E.canPickUp(from: .tableau(0), index: 0, in: s))
        #expect(!E.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: s))
        #expect(E.canPickUp(from: .tableau(0), index: 1, in: s))
    }

    @Test func aMoveCountsOnceAndMovesTheCards() {
        var s = board(columns: [cards("9C 7H"), cards("8S")])
        E.apply(Move(source: .tableau(0), index: 1, destination: .tableau(1)), to: &s)
        #expect(s.tableau[0] == cards("9C") && s.tableau[1] == cards("8S 7H") && s.moveCount == 1)
    }
}

// MARK: - Runs and the run limit

@Suite struct Runs {
    /// An alternating run, Q♠ down to 2♣.
    static let run = cards("QS JH TC 9D 8S 7H 6C 5D 4S 3H 2C")

    /// A position where the last `length` cards of column 1's run may move onto column 2 — or, with
    /// `intoEmpty`, into an empty column — with `emptyCells` free cells and `emptyColumns` empty
    /// columns (the destination among them when it is empty).
    static func position(length: Int, emptyCells: Int, emptyColumns: Int, intoEmpty: Bool) -> (GameState, Move) {
        let first = run[run.count - length]
        var used = Set(run)
        var destination: [Card] = []
        if !intoEmpty {
            let suit = Suit.allCases.first { $0.isRed != first.suit.isRed && !used.contains(Card(suit: $0, rank: first.rank + 1)) }!
            destination = [Card(suit: suit, rank: first.rank + 1)]
            used.formUnion(destination)
        }
        var fillers = (0..<52).map { Card(suit: Suit(rawValue: $0 % 4)!, rank: $0 / 4 + 1) }.filter { !used.contains($0) }
        let take = { () -> Card in fillers.removeFirst() }
        var columns: [[Card]] = [run, destination]
        let emptyAfter = intoEmpty ? emptyColumns - 1 : emptyColumns     // column 2 is one of them when empty
        for i in 0..<6 { columns.append(i < emptyAfter ? [] : [take()]) }
        let cells: [Card?] = (0..<4).map { $0 < emptyCells ? nil : take() }
        let s = board(columns: columns, cells: cells)
        return (s, Move(source: .tableau(0), index: run.count - length, destination: .tableau(1)))
    }

    @Test(arguments: [(4, 0, 5), (0, 0, 1), (3, 0, 4), (2, 1, 6), (1, 2, 8), (4, 1, 10)])
    func ontoACardTheLimitIsCellsPlusOneTimesTwoPerEmptyColumn(cells: Int, columns: Int, limit: Int) {
        let (s, fits) = Self.position(length: limit, emptyCells: cells, emptyColumns: columns, intoEmpty: false)
        #expect(E.maxRun(onto: .tableau(1), in: s) == limit)
        #expect(E.canMove(fits, in: s), "a run of \(limit) moves")
        let (t, tooLong) = Self.position(length: limit + 1, emptyCells: cells, emptyColumns: columns, intoEmpty: false)
        #expect(!E.canMove(tooLong, in: t), "a run of \(limit + 1) doesn't")
    }

    @Test(arguments: [(4, 1, 5), (2, 2, 6), (0, 3, 4), (0, 1, 1)])
    func intoAnEmptyColumnItCountsWithoutThatColumn(cells: Int, columns: Int, limit: Int) {
        let (s, fits) = Self.position(length: limit, emptyCells: cells, emptyColumns: columns, intoEmpty: true)
        #expect(E.maxRun(onto: .tableau(1), in: s) == limit)
        #expect(E.canMove(fits, in: s))
        let (t, tooLong) = Self.position(length: limit + 1, emptyCells: cells, emptyColumns: columns, intoEmpty: true)
        #expect(!E.canMove(tooLong, in: t))
    }

    @Test func aRunMovesAsOneMove() {
        var (s, move) = Self.position(length: 5, emptyCells: 4, emptyColumns: 0, intoEmpty: false)
        E.apply(move, to: &s)
        #expect(s.moveCount == 1 && s.tableau[1].count == 6 && s.tableau[0].count == 6)
    }
}

// MARK: - Tap-to-move

@Suite struct TapToMove {
    @Test func aFoundationComesFirst() {
        let s = board(columns: [cards("AS"), cards("2D")])
        #expect(E.autoDestination(for: .tableau(0), index: 0, in: s) == .foundation(0))
    }

    @Test func thenAColumnScanningFromTheNextOne() {
        let s = board(columns: [cards("5C 7H"), cards("8S"), [], cards("8C")])
        #expect(E.autoDestination(for: .tableau(0), index: 1, in: s) == .tableau(1))
        let t = board(columns: [cards("8C"), cards("5C 7H"), cards("8S")])
        #expect(E.autoDestination(for: .tableau(1), index: 1, in: t) == .tableau(2), "after its own column first")
    }

    @Test func thenAFreeCellThenAnEmptyColumn() {
        let s = board(columns: [cards("5C 7H"), []])
        #expect(E.autoDestination(for: .tableau(0), index: 1, in: s) == .cell(0))
        let run = board(columns: [cards("KD 8S 7H"), []])
        #expect(E.autoDestination(for: .tableau(0), index: 1, in: run) == .tableau(1), "a run can't use a cell")
    }

    @Test func aCellCardNeverGoesToAnotherCell() {
        let s = board(columns: [cards("3C"), []], cells: [c("7H")])
        #expect(E.autoDestination(for: .cell(0), index: 0, in: s) == .tableau(1))
    }

    @Test func aLoneCardStaysPutRatherThanChangeColumns() {
        let full: [Card?] = cards("2C 2D 2H 2S")
        let s = board(columns: [cards("7H"), []], cells: full)
        #expect(E.autoDestination(for: .tableau(0), index: 0, in: s) == nil)
    }

    @Test func nothingLegalIsNil() {
        let full: [Card?] = cards("2C 2D 2H 2S")
        // Every column holds a card, none of them a black 8, and every cell is full.
        let s = board(columns: [cards("5C 7H"), cards("9S"), cards("KH"), cards("QD"), cards("JD"),
                                cards("TH"), cards("4C"), cards("3D")], cells: full)
        #expect(E.autoDestination(for: .tableau(0), index: 1, in: s) == nil)
    }
}

// MARK: - Playing cards home automatically

@Suite struct AutomaticPlays {
    @Test func acesAndTwosAreAlwaysSafe() {
        let s = board()
        #expect(E.isSafeToPlayHome(c("AH"), in: s) && E.isSafeToPlayHome(c("2S"), in: s))
    }

    @Test func aCardIsSafeOnceBothOtherColourFoundationsAreOneBehind() {
        let s = board(foundations: [foundation(.clubs, upTo: 5), foundation(.spades, upTo: 4),
                                    foundation(.hearts, upTo: 5)])
        #expect(!E.isSafeToPlayHome(c("6H"), in: s), "spades are only at 4")
        let t = board(foundations: [foundation(.clubs, upTo: 5), foundation(.spades, upTo: 5),
                                    foundation(.hearts, upTo: 5)])
        #expect(E.isSafeToPlayHome(c("6H"), in: t))
        #expect(!E.isSafeToPlayHome(c("3C"), in: t), "diamonds haven't started")
    }

    @Test func settlePlaysEverySafeCardAndCostsNoMoves() {
        var s = board(columns: [cards("6H"), cards("4D"), cards("6C")], cells: [c("AD")],
                      foundations: [foundation(.clubs, upTo: 5), foundation(.spades, upTo: 5),
                                    foundation(.hearts, upTo: 5), foundation(.diamonds, upTo: 0)])
        s.foundations[3] = []
        let made = E.settle(&s)
        #expect(made.count == 2, "A♦ and 6♥; 4♦ needs 2♦ and 3♦ first, and 6♣ needs the reds at 5")
        #expect(s.tableau[0].isEmpty && s.cells[0] == nil && s.moveCount == 0)
        #expect(s.tableau[2] == cards("6C"))
    }

    @Test func aPlayableButNeededCardStays() {
        var s = board(columns: [cards("3H")], foundations: [foundation(.hearts, upTo: 2), foundation(.clubs, upTo: 1),
                                                            foundation(.spades, upTo: 2)])
        #expect(E.nextSafePlay(in: s) == nil, "a black 2 might still want the 3♥")
        #expect(E.settle(&s).isEmpty)
    }
}

// MARK: - Finish and winning

@Suite struct FinishAndWin {
    static let nearlyWon = board(columns: [cards("KC QC JC"), cards("KD QD JD"), cards("KH QH JH"), cards("KS QS JS")],
                                 foundations: [foundation(.clubs, upTo: 10), foundation(.diamonds, upTo: 10),
                                               foundation(.hearts, upTo: 10), foundation(.spades, upTo: 10)])

    @Test func finishIsOfferedOnceEveryColumnIsInOrder() {
        #expect(E.canAutoFinish(Self.nearlyWon))
        #expect(E.canAutoFinish(board(columns: [cards("KS QS 5D"), cards("9H 2C")])))
        #expect(!E.canAutoFinish(board(columns: [cards("5D 9H")])), "a 9 on a 5")
        #expect(!E.canAutoFinish(board(columns: [cards("7S 7H")])), "equal ranks are out of order")
    }

    @Test func finishPlaysTheLowestCardHomeUntilWon() {
        var s = Self.nearlyWon
        var ranks: [Int] = []
        while let m = E.nextAutoFinishMove(in: s) {
            ranks.append(s[m.source].last!.rank)
            E.applyAutomatic(m, to: &s)
        }
        #expect(ranks == [11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13])
        #expect(s.isWon && s.moveCount == 0)
    }

    @Test func aWonGameNeverChanges() {
        var s = Self.nearlyWon
        while let m = E.nextAutoFinishMove(in: s) { E.applyAutomatic(m, to: &s) }
        #expect(legalMoves(s).isEmpty && !E.canAutoFinish(s) && E.nextSafePlay(in: s) == nil)
    }
}

// MARK: - Invariants over real play

@Suite struct RandomPlay {
    @Test(arguments: [1, 617, 24301])
    func randomPlayKeepsEveryCardAndCountsEachPlayerMove(number: Int) {
        var s = E.newGame(number: number)
        var g = SeededGenerator(state: UInt64(number))
        var playerMoves = 0
        for _ in 0..<200 {
            let moves = legalMoves(s)
            guard let m = moves.randomElement(using: &g) else { break }
            E.apply(m, to: &s)
            playerMoves += 1
            E.settle(&s)
            #expect(Set(allCards(s)).count == 52 && allCards(s).count == 52)
        }
        #expect(s.moveCount == playerMoves)
    }

    @Test func aGameSavesAndLoadsExactly() throws {
        var s = E.newGame(number: 617, hardCore: true)
        s.cells[1] = s.tableau[3].removeLast()
        s.moveCount = 4; s.elapsed = 33; s.undos = 1; s.isRestarted = true
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
