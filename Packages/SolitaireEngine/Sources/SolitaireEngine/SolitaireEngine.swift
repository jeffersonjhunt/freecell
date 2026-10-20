import Foundation

/// Standard Klondike as pure functions over `GameState`. No function throws for a rejected move:
/// it returns `nil` or `false`, so the UI can simply not animate.
public enum SolitaireEngine {

    // MARK: Deal

    /// A fresh deal: column i gets i+1 cards with only its last card face up; the other 24 cards
    /// form the stock, face down. `hardCore`: passes through the deck are limited.
    /// The same deal again from the start (spec "Restart"): the same cards, draw mode and Hard
    /// Core, with moves, time, passes and undos back to none — marked restarted, so it scores 0.
    public static func restart(_ state: GameState) -> GameState {
        var fresh = newGame(drawCount: state.drawCount, seed: state.seed, hardCore: state.isHardCore)
        fresh.isRestarted = true
        return fresh
    }

    public static func newGame(drawCount: Int, seed: UInt64, hardCore: Bool = false) -> GameState {
        precondition(drawCount == 1 || drawCount == 3, "drawCount must be 1 or 3")
        var deck = Suit.allCases.flatMap { suit in (1...13).map { Card(suit: suit, rank: $0) } }
        var rng = SplitMix64(seed: seed)
        deck.seededShuffle(using: &rng)

        var tableau = Array(repeating: [Card](), count: 7)
        for column in 0..<7 {
            for _ in 0...column {
                tableau[column].append(deck.removeLast())
            }
            tableau[column][column].isFaceUp = true
        }
        return GameState(stock: deck, waste: [], foundations: Array(repeating: [], count: 4),
                         tableau: tableau, drawCount: drawCount, seed: seed, isHardCore: hardCore)
    }

    // MARK: Moves

    /// Once the game is won nothing moves any more, so a won game cannot be un-won.
    public static func canMove(_ move: Move, in state: GameState) -> Bool {
        guard !state.isWon, let run = movableRun(from: move.source, index: move.index, in: state),
              let first = run.first,
              move.source != move.destination else { return false }

        switch move.destination {
        case .stock, .waste:
            return false

        case .foundation(let f):
            guard (0..<4).contains(f), run.count == 1 else { return false }
            // Only the waste top and a column's last card go up; foundation-to-foundation is not
            // a Klondike move.
            if case .foundation = move.source { return false }
            return canPlaceOnFoundation(first, state.foundations[f])

        case .tableau(let t):
            guard (0..<7).contains(t) else { return false }
            guard let top = state.tableau[t].last else { return first.rank == 13 }
            return top.isFaceUp && first.rank == top.rank - 1 && first.suit.isRed != top.suit.isRed
        }
    }

    /// Applies a legal move. The card it uncovers in the source column, if face down, flips face up
    /// as part of the same move (one undo step, one move count).
    public static func apply(_ move: Move, to state: inout GameState) {
        precondition(canMove(move, in: state), "apply called with an illegal move: \(move)")
        let run = Array(state[move.source][move.index...])
        state[move.source].removeSubrange(move.index...)
        state[move.destination].append(contentsOf: run)
        if case .tableau(let t) = move.source, let last = state.tableau[t].indices.last,
           !state.tableau[t][last].isFaceUp {
            state.tableau[t][last].isFaceUp = true
        }
        state.moveCount += 1
        state.isWon = isWon(state)
    }

    /// Tapping the stock: draw `drawCount` cards (fewer if the stock runs short) onto the waste,
    /// face up; with the stock empty, turn the waste back over into the stock. Either counts as
    /// one move. With both empty, or once the game is won, it does nothing.
    /// The stock is empty, the waste is not, and a pass remains (Hard Core limits them).
    public static func canRedeal(_ state: GameState) -> Bool {
        guard !state.isWon, state.stock.isEmpty, !state.waste.isEmpty else { return false }
        return state.maxPasses.map { state.passes < $0 } ?? true
    }

    /// Hard Core with its passes used up: the stock is empty, the waste is not, and no redeal is
    /// left (the stock shows ✕).
    public static func isOutOfPasses(_ state: GameState) -> Bool {
        !state.isWon && state.stock.isEmpty && !state.waste.isEmpty && !canRedeal(state)
    }

    public static func drawFromStock(_ state: inout GameState) {
        guard !state.isWon else { return }
        if state.stock.isEmpty {
            guard canRedeal(state) else { return }               // nothing to turn over, or no pass left
            state.stock = state.waste.reversed().map { card in
                var c = card
                c.isFaceUp = false
                return c
            }
            state.waste = []
            state.redeals += 1
        } else {
            for _ in 0..<min(state.drawCount, state.stock.count) {
                var card = state.stock.removeLast()
                card.isFaceUp = true
                state.waste.append(card)
            }
        }
        state.moveCount += 1
    }

    /// Whether the card at `index` in `source` may be picked up (dragged): a face-up card with a
    /// built run on top of it in a column, or the top card of the waste or a foundation. Never the
    /// stock, and nothing once the game is won.
    public static func canPickUp(from source: PileID, index: Int, in state: GameState) -> Bool {
        !state.isWon && movableRun(from: source, index: index, in: state) != nil
    }

    // MARK: Tap-to-move

    /// Where a tap on the card at `index` in `source` sends it (with the run above it), or nil.
    ///
    /// In order: a foundation, if it is a single card; then a non-empty tableau column that accepts
    /// the run, scanning left to right starting after the source column; then an empty column —
    /// unless the run already sits alone at the bottom of a column, which would be a no-op.
    ///
    /// A tap on a foundation card does nothing: taps send cards toward the foundations, and a
    /// missed tap must never pull one back down. Taking a card off a foundation is drag-only.
    public static func autoDestination(for source: PileID, index: Int, in state: GameState) -> PileID? {
        if case .foundation = source { return nil }
        guard let run = movableRun(from: source, index: index, in: state) else { return nil }

        if run.count == 1 {
            for f in 0..<4 where canMove(Move(source: source, index: index, destination: .foundation(f)), in: state) {
                return .foundation(f)
            }
        }

        let start: Int
        if case .tableau(let s) = source { start = s + 1 } else { start = 0 }
        let order = (0..<7).map { (start + $0) % 7 }

        for t in order where !state.tableau[t].isEmpty
            && canMove(Move(source: source, index: index, destination: .tableau(t)), in: state) {
            return .tableau(t)
        }

        if case .tableau = source, index == 0 { return nil }
        for t in order where state.tableau[t].isEmpty
            && canMove(Move(source: source, index: index, destination: .tableau(t)), in: state) {
            return .tableau(t)
        }
        return nil
    }

    // MARK: Auto-finish and winning

    /// Offered when the stock and waste are empty and every tableau card is face up — the game
    /// can then always be finished.
    public static func canAutoFinish(_ state: GameState) -> Bool {
        !state.isWon && state.stock.isEmpty && state.waste.isEmpty
            && state.tableau.allSatisfy { $0.allSatisfy(\.isFaceUp) }
    }

    /// The next auto-finish step: the lowest-ranked card that can go to a foundation (leftmost
    /// column on a tie), or nil when none can.
    public static func nextAutoFinishMove(in state: GameState) -> Move? {
        var best: (move: Move, rank: Int)?
        for t in 0..<7 {
            guard let card = state.tableau[t].last else { continue }
            let index = state.tableau[t].count - 1
            for f in 0..<4 {
                let move = Move(source: .tableau(t), index: index, destination: .foundation(f))
                if canMove(move, in: state), best == nil || card.rank < best!.rank {
                    best = (move, card.rank)
                    break
                }
            }
        }
        return best?.move
    }

    // MARK: Scoring (spec "Scoring")

    /// The most a win's time bonus can be: all of it, under a minute.
    public static let maxTimeBonus = 600

    /// The score: the play score, plus the time bonus once the game is won. A restarted game
    /// scores 0.
    public static func score(_ state: GameState) -> Int {
        guard !state.isRestarted else { return 0 }
        return playScore(state) + (isWon(state) ? timeBonus(seconds: Int(state.elapsed)) : 0)
    }

    /// The points earned in play, worked out from the game itself: +5 per card on a foundation,
    /// +35 per complete suit, −3 per undo, −100 per redeal; never below 0.
    public static func playScore(_ state: GameState) -> Int {
        guard !state.isRestarted else { return 0 }
        let onFoundations = state.foundations.reduce(0) { $0 + $1.count }
        let suits = state.foundations.filter { $0.count == 13 }.count
        return max(5 * onFoundations + 35 * suits - 3 * state.undos - 100 * state.redeals, 0)
    }

    /// What a win adds for its time: 600 less the time penalty, never below 0.
    public static func timeBonus(seconds: Int) -> Int {
        max(maxTimeBonus - timePenalty(seconds: seconds), 0)
    }

    /// Free for the first minute; then 1 point a second in the second minute, 2 in the third, and so
    /// on: 60 by 2:00, 180 by 3:00, 600 by 5:00.
    public static func timePenalty(seconds: Int) -> Int {
        guard seconds > 60 else { return 0 }
        let past = seconds - 60
        let minutes = past / 60, rest = past % 60
        return 60 * minutes * (minutes + 1) / 2 + rest * (minutes + 1)
    }

    public static func isWon(_ state: GameState) -> Bool {
        state.foundations.count == 4 && state.foundations.allSatisfy { $0.count == 13 }
    }

    // MARK: Helpers

    /// The cards that would move if `index` in `source` were picked up — a slice, so it keeps the
    /// pile's indices (use `first`, never `[0]`) — if picking it up is allowed at all: only the top card of the waste or a foundation, and from a column only a
    /// face-up card together with the (properly built) run on top of it.
    static func movableRun(from source: PileID, index: Int, in state: GameState) -> ArraySlice<Card>? {
        switch source {
        case .stock:
            return nil
        case .waste:
            guard index == state.waste.count - 1, index >= 0 else { return nil }
        case .foundation(let f):
            // Redundant with the built-run check below (a foundation ascends in one suit, so any
            // slice of two or more is never a built run) — kept so the rule reads as stated.
            guard (0..<4).contains(f), index == state.foundations[f].count - 1, index >= 0 else { return nil }
        case .tableau(let t):
            guard (0..<7).contains(t), state.tableau[t].indices.contains(index) else { return nil }
        }
        let run = state[source][index...]
        guard run.allSatisfy(\.isFaceUp) else { return nil }
        for (lower, upper) in zip(run, run.dropFirst())
        where upper.rank != lower.rank - 1 || upper.suit.isRed == lower.suit.isRed {
            return nil
        }
        return run
    }

    static func canPlaceOnFoundation(_ card: Card, _ foundation: [Card]) -> Bool {
        guard let top = foundation.last else { return card.rank == 1 }
        return card.suit == top.suit && card.rank == top.rank + 1
    }
}
