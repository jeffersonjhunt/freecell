import Foundation
import Testing
@testable import SolitaireEngine

typealias E = SolitaireEngine

// MARK: - Deal (acceptance: 52 distinct cards, 28 in the tableau with 7 face up, 24 in the stock)

@Suite struct Deal {
    @Test(arguments: [0, 1, 42, 2026, UInt64.max])
    func newDealHasTheRightShape(seed: UInt64) {
        for drawCount in [1, 3] {
            let s = E.newGame(drawCount: drawCount, seed: seed)
            #expect(Set(allCards(s).map(\.id)).count == 52)
            #expect(allCards(s).count == 52)
            #expect(s.tableau.map(\.count) == [1, 2, 3, 4, 5, 6, 7])
            #expect(s.tableau.flatMap { $0 }.filter(\.isFaceUp).count == 7)
            #expect(s.tableau.allSatisfy { $0.last!.isFaceUp })
            #expect(s.stock.count == 24 && s.stock.allSatisfy { !$0.isFaceUp })
            #expect(s.waste.isEmpty && s.foundations == [[], [], [], []])
            #expect(s.drawCount == drawCount && s.moveCount == 0 && !s.isWon && s.seed == seed)
        }
    }

    @Test func sameSeedSameDealDifferentSeedDifferentDeal() {
        #expect(E.newGame(drawCount: 1, seed: 7) == E.newGame(drawCount: 1, seed: 7))
        #expect(E.newGame(drawCount: 1, seed: 7) != E.newGame(drawCount: 1, seed: 8))
    }

    /// SplitMix64's published reference output for seed 0.
    @Test func splitMixMatchesTheReference() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
    }

    /// Pins the deal for one seed, so the same seed deals the same game on every platform and
    /// Swift version (this test runs on macOS and on Linux).
    @Test func dealIsStableAcrossPlatforms() {
        let s = E.newGame(drawCount: 1, seed: 42)
        #expect(s.tableau.map { $0.last!.id } == GoldenDeal.seed42Tops)
        #expect(s.stock.map(\.id) == GoldenDeal.seed42Stock)
    }
}

// MARK: - Legal and illegal moves (acceptance: every rule allowed, everything else refused)

@Suite struct Moves {
    func can(_ s: GameState, _ src: PileID, _ i: Int, _ dst: PileID) -> Bool {
        E.canMove(Move(source: src, index: i, destination: dst), in: s)
    }

    @Test func toFoundation() {
        let s = board(tableau: [[down("5C"), up("2H")], [up("9S"), up("8H")]],
                      waste: [up("3D"), up("AS")],
                      foundations: [[], foundation(.hearts, upTo: 1)])
        #expect(can(s, .waste, 1, .foundation(0)))            // ace onto an empty foundation
        #expect(can(s, .waste, 1, .foundation(2)))            // any empty foundation
        #expect(!can(s, .waste, 1, .foundation(1)))           // ace onto a non-empty one
        #expect(can(s, .tableau(0), 1, .foundation(1)))       // 2♥ on A♥: same suit, one higher
        #expect(!can(s, .tableau(0), 1, .foundation(0)))      // 2 onto empty
        #expect(!can(s, .waste, 0, .foundation(0)))           // not the waste top
        #expect(!can(s, .tableau(1), 0, .foundation(0)))      // a run of two cannot go up
        // …even when its first card fits: 2♥ (with A♠ on it) onto A♥ would bury the A♠.
        let fits = board(tableau: [[up("2H"), up("AS")]], foundations: [foundation(.hearts, upTo: 1)])
        #expect(!can(fits, .tableau(0), 0, .foundation(0)))
        #expect(can(fits, .tableau(0), 1, .foundation(1)))    // the A♠ alone may go
    }

    @Test func foundationNeedsSameSuitAndNextRank() {
        let s = board(tableau: [[up("3H")], [up("3D")], [up("4H")]],
                      foundations: [foundation(.hearts, upTo: 2)])
        #expect(can(s, .tableau(0), 0, .foundation(0)))
        #expect(!can(s, .tableau(1), 0, .foundation(0)))      // wrong suit
        #expect(!can(s, .tableau(2), 0, .foundation(0)))      // skips a rank
    }

    @Test func tableauToTableau() {
        let s = board(tableau: [[down("2C"), up("9H"), up("8C"), up("7D")],
                                [up("10S")], [up("10H")], [up("9S")], [], [down("KC")]])
        #expect(can(s, .tableau(0), 1, .tableau(1)))          // 9♥-8♣-7♦ onto 10♠
        #expect(!can(s, .tableau(0), 1, .tableau(2)))         // same colour
        #expect(!can(s, .tableau(0), 1, .tableau(3)))         // wrong rank
        #expect(!can(s, .tableau(0), 2, .tableau(3)))         // 8♣ onto 9♠: same colour
        #expect(!can(s, .tableau(0), 3, .tableau(0)))         // onto its own pile
        #expect(!can(s, .tableau(0), 0, .tableau(1)))         // a face-down card
        #expect(!can(s, .tableau(0), 1, .tableau(4)))         // only a king onto an empty column
        #expect(!can(s, .tableau(3), 0, .tableau(5)))         // onto a face-down card
        // Rank and colour both fit, so only the face-down check can refuse these:
        let hidden = board(tableau: [[up("9S")], [down("10H")]])
        #expect(!can(hidden, .tableau(0), 0, .tableau(1)))
        // 9♥-8♠-7♠ is not a built run (7♠ on 8♠), though 9♥ itself fits the 10♠:
        let unbuilt = board(tableau: [[up("9H"), up("8S"), up("7S")], [up("10S")]])
        #expect(!can(unbuilt, .tableau(0), 0, .tableau(1)))
        #expect(E.autoDestination(for: .tableau(0), index: 0, in: unbuilt) == nil)
    }

    @Test func kingWithItsRunOntoAnEmptyColumn() {
        let s = board(tableau: [[down("2C"), up("KH"), up("QS")], []])
        #expect(can(s, .tableau(0), 1, .tableau(1)))
        #expect(!can(s, .tableau(0), 2, .tableau(1)))         // queen alone may not
    }

    @Test func wasteToTableau() {
        let s = board(tableau: [[up("8S")]], waste: [up("7C"), up("7H")])
        #expect(can(s, .waste, 1, .tableau(0)))
        #expect(!can(s, .waste, 0, .tableau(0)))              // only the top of the waste
    }

    @Test func foundationBackToTableau() {
        let s = board(tableau: [[up("4C")], [up("4H")], [up("3C")]],
                      foundations: [foundation(.hearts, upTo: 3)])
        #expect(can(s, .foundation(0), 2, .tableau(0)))       // 3♥ onto 4♣
        #expect(!can(s, .foundation(0), 2, .tableau(1)))      // same colour
        #expect(!can(s, .foundation(0), 1, .tableau(2)))      // 2♥ would fit 3♣, but is not the top
        #expect(!can(s, .foundation(0), 2, .foundation(1)))   // foundation to foundation
        // An ace could sit on any empty foundation — but never by moving between foundations.
        let ace = board(foundations: [foundation(.hearts, upTo: 1)])
        #expect(!can(ace, .foundation(0), 0, .foundation(1)))
    }

    @Test func nothingElse() {
        let s = board(tableau: [[up("KS"), up("QH"), up("5D")], [up("6C")]],
                      waste: [up("AS")], stock: [down("2D")])
        #expect(!can(s, .stock, 0, .waste))                   // drawing is not a move
        #expect(!can(s, .waste, 0, .stock))
        #expect(!can(s, .waste, 0, .waste))
        #expect(!can(s, .tableau(0), 0, .tableau(1)))         // K-Q-5 is not a built run
        #expect(!can(s, .tableau(9), 0, .tableau(1)))
        #expect(!can(s, .tableau(1), 0, .tableau(9)))
        #expect(!can(s, .tableau(1), 0, .foundation(4)))
        #expect(!can(s, .tableau(1), -1, .tableau(0)))
        #expect(!can(s, .tableau(1), 1, .tableau(0)))
        #expect(!can(board(), .waste, 0, .foundation(0)))     // empty waste
    }

    @Test func applyMovesTheRunAndFlipsTheUncoveredCardInOneMove() {
        var s = board(tableau: [[down("2C"), up("9H"), up("8C")], [up("10S")]])
        E.apply(Move(source: .tableau(0), index: 1, destination: .tableau(1)), to: &s)
        #expect(s.tableau[1].map(\.id) == [up("10S"), up("9H"), up("8C")].map(\.id))
        #expect(s.tableau[0] == [up("2C")])
        #expect(s.moveCount == 1)
    }

    @Test func applyDetectsTheWin() {
        var s = board(tableau: [[up("KS")]],
                      foundations: [foundation(.spades, upTo: 12), foundation(.hearts, upTo: 13),
                                    foundation(.diamonds, upTo: 13), foundation(.clubs, upTo: 13)])
        #expect(!s.isWon)
        E.apply(Move(source: .tableau(0), index: 0, destination: .foundation(0)), to: &s)
        #expect(s.isWon && E.isWon(s))
    }
}

// MARK: - Stock, draw modes and redeal (acceptance: draw 3 plays only the top; redeal reverses)

@Suite struct Stock {
    @Test func drawOneTurnsUpTheTopCard() {
        var s = board(stock: [down("2C"), down("7H")])
        E.drawFromStock(&s)
        #expect(s.waste == [up("7H")] && s.stock == [down("2C")] && s.moveCount == 1)
    }

    @Test func drawThreeOnlyTheTopOfTheWasteIsPlayable() {
        var s = board(tableau: [[up("8S")], [up("9C")]],
                      stock: [down("AD"), down("8H"), down("7D"), down("6D")], drawCount: 3)
        E.drawFromStock(&s)
        #expect(s.waste.map(\.id) == [up("6D"), up("7D"), up("8H")].map(\.id))  // 8♥ drawn last, on top
        #expect(s.waste.allSatisfy { $0.isFaceUp } && s.stock == [down("AD")])
        #expect(E.canMove(Move(source: .waste, index: 2, destination: .tableau(1)), in: s))   // 8♥ on 9♣
        #expect(!E.canMove(Move(source: .waste, index: 1, destination: .tableau(0)), in: s))  // 7♦ under it
        E.drawFromStock(&s)                                      // only one left: draws one
        #expect(s.waste.count == 4 && s.stock.isEmpty)
    }

    /// Under a draw-3 fan the cards often look like a built run (7♦ then 6♣); only the top card
    /// may still be played — never the card beneath it with the top riding along.
    @Test func cardsUnderTheWasteTopStayPutEvenWhenTheyLookLikeARun() {
        let s = board(tableau: [[up("8S")]], waste: [up("7D"), up("6C")], drawCount: 3)
        #expect(!E.canMove(Move(source: .waste, index: 0, destination: .tableau(0)), in: s))
        #expect(E.autoDestination(for: .waste, index: 0, in: s) == nil)
    }

    @Test(arguments: [1, 3])
    func redealRestoresTheStockInReverseSoTheSameCardsComeUpAgain(drawCount: Int) {
        var s = E.newGame(drawCount: drawCount, seed: 99)
        let stockBefore = s.stock
        var firstPass: [[Card]] = []
        while !s.stock.isEmpty { E.drawFromStock(&s); firstPass.append(s.waste) }
        let moves = s.moveCount

        #expect(s.redeals == 0 && s.passes == 1, "draws alone stay on the first pass")
        E.drawFromStock(&s)                                      // redeal
        #expect(s.moveCount == moves + 1, "a redeal counts as one move")
        #expect(s.redeals == 1 && s.passes == 2, "a redeal starts the second pass")
        #expect(s.waste.isEmpty)
        #expect(s.stock == stockBefore, "same order, face down")
        #expect(s.stock.map(\.id) == firstPass.last!.reversed().map(\.id))

        var secondPass: [[Card]] = []
        while !s.stock.isEmpty { E.drawFromStock(&s); secondPass.append(s.waste) }
        #expect(secondPass == firstPass)
    }

    @Test func tappingAnEmptyStockWithAnEmptyWasteDoesNothing() {
        var s = board()
        E.drawFromStock(&s)
        #expect(s == board() && s.moveCount == 0)
    }
}

// MARK: - Pick-up (drag): face-up cards only, and only the top of the waste or a foundation

@Suite struct PickUp {
    @Test func whatMayBeDragged() {
        let s = board(tableau: [[down("2C"), up("9H"), up("8C")], [up("KS"), up("QH"), up("5D")]],
                      waste: [up("7C"), up("7H")], stock: [down("3D")],
                      foundations: [foundation(.spades, upTo: 2)])
        #expect(E.canPickUp(from: .tableau(0), index: 1, in: s))        // 9♥ with 8♣ on it
        #expect(E.canPickUp(from: .tableau(0), index: 2, in: s))
        #expect(!E.canPickUp(from: .tableau(0), index: 0, in: s))       // face down
        #expect(!E.canPickUp(from: .tableau(1), index: 0, in: s))       // K-Q-5 is not a built run
        #expect(E.canPickUp(from: .waste, index: 1, in: s))
        #expect(!E.canPickUp(from: .waste, index: 0, in: s))            // under the waste top
        #expect(E.canPickUp(from: .foundation(0), index: 1, in: s))
        #expect(!E.canPickUp(from: .foundation(0), index: 0, in: s))
        #expect(!E.canPickUp(from: .stock, index: 0, in: s))
        var won = s
        won.isWon = true
        #expect(!E.canPickUp(from: .tableau(0), index: 2, in: won))
    }
}

// MARK: - Tap-to-move (acceptance: never a no-op; king to an empty column by drag, not by tap)

@Suite struct TapToMove {
    func dest(_ s: GameState, _ src: PileID, _ i: Int) -> PileID? {
        E.autoDestination(for: src, index: i, in: s)
    }

    @Test func aSingleCardPrefersTheFoundation() {
        let s = board(tableau: [[up("2H")], [up("3S")]], foundations: [[], foundation(.hearts, upTo: 1)])
        #expect(dest(s, .tableau(0), 0) == .foundation(1))
    }

    @Test func runsGoToTheFirstFittingColumnAfterTheSourceWrappingAround() {
        let s = board(tableau: [[up("10D")], [], [up("8S")], [up("9C"), up("8H")], [], [up("9S")], [up("10H")]])
        // 9♣-8♥ at column 3 fits 10♦ (col 0) and 10♥ (col 6): scanning 4,5,6,0… picks 6.
        #expect(dest(s, .tableau(3), 0) == .tableau(6))
        #expect(dest(s, .tableau(5), 0) == .tableau(6))        // 9♠ → 10♥, never an empty column first
        // Wrap-around: 9♣ at column 5; the only fitting column (10♦) is to its left.
        let wrap = board(tableau: [[up("5S")], [up("10D")], [up("6S")], [up("7S")], [], [up("9C")], [up("8S")]])
        #expect(dest(wrap, .tableau(5), 0) == .tableau(1))
    }

    /// Taps send cards toward the foundations; a tap never pulls one back down.
    @Test func tappingAFoundationCardDoesNothing() {
        let s = board(tableau: [[up("4C")], []], foundations: [foundation(.hearts, upTo: 3), foundation(.spades, upTo: 13)])
        #expect(dest(s, .foundation(0), 2) == nil)             // 3♥ would fit the 4♣
        #expect(dest(s, .foundation(1), 12) == nil)            // K♠ would fit the empty column
        #expect(E.canMove(Move(source: .foundation(0), index: 2, destination: .tableau(0)), in: s),
                "still possible by drag")
    }

    @Test func emptyColumnIsTheLastResortAndNeverANoOp() {
        let buried = board(tableau: [[down("3C"), up("KH")], []])
        #expect(dest(buried, .tableau(0), 1) == .tableau(1))   // uncovers a card: offered
        let alone = board(tableau: [[up("KH")], []])
        #expect(dest(alone, .tableau(0), 0) == nil)            // would only shuffle columns
        #expect(E.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: alone),
                "still possible by drag")
    }

    @Test func nothingFitsReturnsNil() {
        let s = board(tableau: [[up("5S")], [up("9H")]])
        #expect(dest(s, .tableau(0), 0) == nil)
        #expect(dest(s, .stock, 0) == nil)
    }

    /// Over many real positions: a tap target is always legal, and never a move that changes
    /// nothing (same pile, or a whole column onto an empty column).
    @Test func tapIsAlwaysLegalAndNeverANoOp() {
        var checked = 0
        for seed in UInt64(1)...40 {
            var s = E.newGame(drawCount: 1, seed: seed)
            for step in 0..<300 {
                let sources = [(PileID.waste, s.waste.count - 1)]
                    + (0..<4).map { (PileID.foundation($0), s.foundations[$0].count - 1) }
                    + (0..<7).flatMap { t in s.tableau[t].indices.map { (PileID.tableau(t), $0) } }
                for (src, i) in sources where i >= 0 {
                    guard let d = E.autoDestination(for: src, index: i, in: s) else { continue }
                    checked += 1
                    #expect(d != src)
                    if case .foundation = src { Issue.record("a tap moved a card off a foundation") }
                    #expect(E.canMove(Move(source: src, index: i, destination: d), in: s))
                    if case .tableau(let t) = d, s.tableau[t].isEmpty, case .tableau = src {
                        #expect(i > 0, "moved a whole column to an empty column")
                    }
                }
                let moves = legalMoves(s)
                if !moves.isEmpty && step % 3 != 0 {
                    E.apply(moves[(Int(seed) + step) % moves.count], to: &s)
                } else {
                    E.drawFromStock(&s)
                }
            }
        }
        #expect(checked > 1000, "the property must actually be exercised (checked \(checked))")
    }
}

// MARK: - Auto-finish and a full game (acceptance: a known-solvable seed plays to a win)

@Suite struct Finish {
    @Test func autoFinishIsOfferedOnlyWhenEverythingIsFaceUpAndDealtOut() {
        let open = board(tableau: [[up("2S"), up("AH")], [up("AS")]])
        #expect(E.canAutoFinish(open))
        #expect(!E.canAutoFinish(board(tableau: [[down("2S"), up("AH")]])))
        #expect(!E.canAutoFinish(board(tableau: [[up("AH")]], waste: [up("2S")])))
        #expect(!E.canAutoFinish(board(tableau: [[up("AH")]], stock: [down("2S")])))
    }

    @Test func autoFinishPlaysTheLowestRankFirstAndWins() {
        var s = board(tableau: [[up("2S"), up("AH")], [up("2H"), up("AS")]],
                      foundations: [[], [], foundation(.diamonds, upTo: 13), foundation(.clubs, upTo: 13)])
        var ranks: [Int] = []
        while let m = E.nextAutoFinishMove(in: s) {
            ranks.append(s[m.source][m.index].rank)
            E.apply(m, to: &s)
        }
        #expect(ranks == [1, 1, 2, 2])
        #expect(s.tableau.allSatisfy { $0.isEmpty })
    }

    @Test func nothingMovesOnceTheGameIsWon() {
        var s = board(foundations: [foundation(.spades, upTo: 13), foundation(.hearts, upTo: 13),
                                    foundation(.diamonds, upTo: 13), foundation(.clubs, upTo: 13)])
        s.isWon = true
        // K♠ onto an empty column is otherwise legal — only the won state refuses it.
        #expect(!E.canMove(Move(source: .foundation(0), index: 12, destination: .tableau(0)), in: s))
        s.stock = [down("2C")]                                  // the stock tap is refused as well
        let before = s
        E.drawFromStock(&s)
        #expect(s == before)
    }

    @Test func aKnownSolvableSeedPlaysToAWin() {
        let end = playGreedily(E.newGame(drawCount: 1, seed: GoldenDeal.solvableSeed))
        #expect(end.isWon)
        #expect(end.foundations.allSatisfy { $0.count == 13 })
        #expect(!E.canAutoFinish(end), "nothing left to offer once won")
    }
}

/// Values pinned from the first run and checked on every platform since.
enum GoldenDeal {
    static let seed42Tops = [9, 8, 2, 50, 24, 49, 16]
    static let seed42Stock = [6, 28, 12, 39, 40, 0, 26, 25, 22, 4, 46, 36, 27, 42, 31, 17,
                              14, 43, 18, 13, 19, 1, 33, 7]
    /// The first seed (of 1...400, 44 winnable) that `playGreedily` wins with draw 1.
    static let solvableSeed: UInt64 = 4
}

// MARK: - Passes through the deck (spec "Draw modes")

@Suite struct Passes {
    @Test func aNewDealIsOnItsFirstPass() {
        #expect(E.newGame(drawCount: 3, seed: 7).passes == 1)
    }

    /// A save written before passes were counted has no `redeals`: it resumes with none.
    @Test func olderSavesResumeWithNoRedeals() throws {
        var s = E.newGame(drawCount: 1, seed: 7)
        s.redeals = 4
        let data = try JSONEncoder().encode(s)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["redeals"] as? Int == 4, "written")
        object.removeValue(forKey: "redeals")
        let old = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.redeals == 0 && old.passes == 1)
        var expected = s
        expected.redeals = 0
        #expect(old == expected, "everything else as saved")
        #expect(try JSONDecoder().decode(GameState.self, from: data) == s, "a round trip keeps the count")
    }
}

// MARK: - Hard Core (spec "Hard Core")

@Suite struct HardCore {
    /// Plays through the stock once (every card drawn), leaving it empty and the waste full.
    func exhaustStock(_ s: inout GameState) {
        while !s.stock.isEmpty { E.drawFromStock(&s) }
    }

    @Test func draw1GetsOnePassNoRedeal() {
        var s = E.newGame(drawCount: 1, seed: 11, hardCore: true)
        #expect(s.isHardCore && s.maxPasses == 1)
        exhaustStock(&s)
        #expect(!E.canRedeal(s) && E.isOutOfPasses(s))
        let before = s
        E.drawFromStock(&s)
        #expect(s == before, "no redeal, not even a move counted")
    }

    @Test func draw3GetsThreePasses() {
        var s = E.newGame(drawCount: 3, seed: 11, hardCore: true)
        #expect(s.maxPasses == 3)
        for pass in 1...3 {
            #expect(s.passes == pass)
            exhaustStock(&s)
            if pass < 3 {
                #expect(E.canRedeal(s) && !E.isOutOfPasses(s), "pass \(pass): a redeal remains")
                E.drawFromStock(&s)
            }
        }
        #expect(E.isOutOfPasses(s) && s.redeals == 2)
        let before = s
        E.drawFromStock(&s)
        #expect(s == before, "no third redeal")
    }

    @Test(arguments: [1, 3])
    func normalGamesRedealWithoutLimit(drawCount: Int) {
        var s = E.newGame(drawCount: drawCount, seed: 11)
        #expect(!s.isHardCore && s.maxPasses == nil)
        for _ in 0..<5 { exhaustStock(&s); #expect(E.canRedeal(s)); E.drawFromStock(&s) }
        #expect(s.redeals == 5 && !E.isOutOfPasses(s))
    }

    /// A save from before Hard Core is a normal game; Hard Core survives a round trip.
    @Test func olderSavesAreNormalGames() throws {
        let s = E.newGame(drawCount: 3, seed: 7, hardCore: true)
        let data = try JSONEncoder().encode(s)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isHardCore")
        let old = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!old.isHardCore)
        #expect(try JSONDecoder().decode(GameState.self, from: data) == s)
    }
}

// MARK: - Scoring (spec "Scoring")

@Suite struct Scoring {
    @Test func aFreshDealIsWorthNothing() {
        #expect(E.score(E.newGame(drawCount: 1, seed: 3)) == 0)
    }

    @Test(arguments: [(0, 600), (60, 600), (61, 599), (120, 540), (180, 420), (240, 240), (300, 0), (390, 0)])
    func theTimeBonusIs600LessThePenalty(seconds: Int, bonus: Int) {
        #expect(E.timeBonus(seconds: seconds) == bonus)
    }

    @Test(arguments: [(0, 0), (60, 0), (61, 1), (120, 60), (121, 62), (180, 180), (240, 360), (300, 600), (390, 1080)])
    func theTimePenaltyEscalatesEachMinute(seconds: Int, penalty: Int) {
        #expect(E.timePenalty(seconds: seconds) == penalty)
    }

    /// The spec's table: a one-pass, no-undo win scores 1000 under a minute, then less with time,
    /// down to the 400 its cards and suits earned.
    @Test(arguments: [(59, 1000), (120, 940), (180, 820), (240, 640), (300, 400), (390, 400)])
    func aOnePassWin(seconds: Int, score: Int) {
        var s = E.newGame(drawCount: 1, seed: 3)
        s.foundations = Suit.allCases.map { suit in (1...13).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        s.tableau = Array(repeating: [], count: 7); s.stock = []; s.waste = []
        s.elapsed = TimeInterval(seconds)
        #expect(E.score(s) == score)
    }

    @Test func cardsSuitsUndosAndRedealsCount() {
        var s = E.newGame(drawCount: 1, seed: 3)
        s.foundations[0] = (1...13).map { Card(suit: .spades, rank: $0, isFaceUp: true) }   // a suit
        s.foundations[1] = [Card(suit: .hearts, rank: 1, isFaceUp: true)]                     // one more card
        #expect(E.score(s) == 5 * 14 + 35)
        s.undos = 2
        #expect(E.score(s) == 70 + 35 - 6)
        s.elapsed = 600
        #expect(E.score(s) == 70 + 35 - 6, "time only costs the win's bonus")
        s.redeals = 1
        #expect(E.score(s) == 0, "a redeal costs more than these cards earned")
        s.foundations[2] = (1...13).map { Card(suit: .diamonds, rank: $0, isFaceUp: true) }   // another suit
        #expect(E.score(s) == 5 * 27 + 70 - 6 - 100, "a redeal's cost is still owed after the floor")
        s.foundations[0].removeLast()                                                          // the king back off
        #expect(E.score(s) == 5 * 26 + 35 - 6 - 100, "the card's 5 and the suit's 35 go")
    }

    @Test func neverBelowZero() {
        var s = E.newGame(drawCount: 3, seed: 3)
        s.redeals = 9
        #expect(E.score(s) == 0)
    }

    /// The bonus comes only with the win, and on top of everything the play earned.
    @Test func theTimeBonusComesWithTheWin() {
        var s = E.newGame(drawCount: 1, seed: 3)
        s.foundations = Suit.allCases.map { suit in (1...13).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        s.tableau = Array(repeating: [], count: 7); s.stock = []; s.waste = []
        s.undos = 2; s.redeals = 1; s.elapsed = 200
        #expect(E.playScore(s) == 400 - 6 - 100)
        #expect(E.score(s) == 294 + 600 - E.timePenalty(seconds: 200))
        s.foundations[3].removeLast()
        #expect(!E.isWon(s) && E.score(s) == E.playScore(s), "no win, no bonus")
    }

    @Test func olderSavesHaveNoUndos() throws {
        var s = E.newGame(drawCount: 1, seed: 7)
        s.undos = 5
        let data = try JSONEncoder().encode(s)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "undos")
        let old = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.undos == 0)
        #expect(try JSONDecoder().decode(GameState.self, from: data) == s)
    }
}

// MARK: - Restart (spec "Restart")

@Suite struct Restarting {
    @Test func theSameDealFromTheStartMarkedRestarted() throws {
        var s = E.newGame(drawCount: 3, seed: 11, hardCore: true)
        let fresh = s
        s.stock.removeLast(3); s.moveCount = 9; s.elapsed = 75; s.undos = 2; s.redeals = 1
        let again = E.restart(s)
        #expect(again.isRestarted)
        var unmarked = again
        unmarked.isRestarted = false
        #expect(unmarked == fresh, "the same cards, mode and Hard Core, with nothing played")
        #expect(!fresh.isRestarted && !E.newGame(drawCount: 1, seed: 11).isRestarted)
    }

    /// A restarted game scores 0, however it is played — a win included.
    @Test func aRestartedGameScoresZero() {
        var s = E.restart(E.newGame(drawCount: 1, seed: 3))
        s.foundations = Suit.allCases.map { suit in (1...13).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        s.tableau = Array(repeating: [], count: 7); s.stock = []; s.waste = []
        s.elapsed = 30
        #expect(E.isWon(s) && E.playScore(s) == 0 && E.score(s) == 0)
        s.isRestarted = false
        #expect(E.score(s) == 1000, "the same win, not restarted")
    }

    @Test func theMarkIsSavedAndOlderSavesWereNeverRestarted() throws {
        let s = E.restart(E.newGame(drawCount: 1, seed: 7))
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(GameState.self, from: data) == s)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isRestarted")
        let old = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!old.isRestarted)
    }
}
