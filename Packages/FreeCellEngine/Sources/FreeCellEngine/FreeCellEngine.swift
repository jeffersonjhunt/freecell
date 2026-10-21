import Foundation

/// FreeCell as pure functions over `GameState` (spec "Game rules"). No function throws for a
/// rejected move: it returns `nil` or `false`, so the UI can simply not animate.
public enum FreeCellEngine {

    // MARK: Game numbers and the deal

    /// Every game number: Microsoft's numbering, as far as the first million.
    public static let numbers = 1...1_000_000

    /// The only numbers among the first million that can't be won (11982 is the only one of the
    /// original 32,000). New Game never deals them; they can still be chosen by number.
    public static let unwinnable: Set<Int> = [11982, 146692, 186216, 455889, 495505, 512118, 517776, 781948]

    /// Free cells in a game: four, or two in Hard Core.
    public static func cellCount(hardCore: Bool) -> Int { hardCore ? 2 : 4 }

    /// Microsoft's deal for `number`: a deck in rank-major order (A♣ A♦ A♥ A♠ 2♣ … K♠), a linear
    /// congruential generator seeded with the number, each card taken at `draw mod (cards left)`
    /// with the last card swapped into its place, dealt across eight columns a row at a time.
    public static func deal(number: Int) -> [[Card]] {
        var deck = (0..<52).map { Card(suit: Suit(rawValue: $0 % 4)!, rank: $0 / 4 + 1) }
        var state = UInt32(truncatingIfNeeded: number)
        var columns = Array(repeating: [Card](), count: 8)
        var dealt = 0
        while !deck.isEmpty {
            state = (state &* 214013 &+ 2531011) & 0x7FFF_FFFF
            let j = Int(state >> 16) % deck.count
            columns[dealt % 8].append(deck[j])
            deck[j] = deck[deck.count - 1]
            deck.removeLast()
            dealt += 1
        }
        return columns
    }

    public static func newGame(number: Int, hardCore: Bool = false) -> GameState {
        precondition(numbers.contains(number), "game numbers run from 1 to 1,000,000")
        return GameState(cells: Array(repeating: nil, count: cellCount(hardCore: hardCore)),
                         foundations: Array(repeating: [], count: 4), tableau: deal(number: number),
                         number: number, isHardCore: hardCore)
    }

    /// This game again from the start (spec "Restart"): the same number and Hard Core, with moves,
    /// time and undos back to none — marked restarted, so its win is never recorded.
    public static func restart(_ state: GameState) -> GameState {
        var fresh = newGame(number: state.number, hardCore: state.isHardCore)
        fresh.isRestarted = true
        return fresh
    }

    /// A game number for New Game: any in range except the eight that can't be won.
    public static func randomNumber<G: RandomNumberGenerator>(using generator: inout G) -> Int {
        while true {
            let n = Int.random(in: numbers, using: &generator)
            if !unwinnable.contains(n) { return n }
        }
    }

    // MARK: Moves

    /// Once the game is won nothing moves any more, so a won game cannot be un-won.
    public static func canMove(_ move: Move, in state: GameState) -> Bool {
        guard !state.isWon, move.source != move.destination,
              let run = movableRun(from: move.source, index: move.index, in: state),
              let first = run.first else { return false }

        switch move.destination {
        case .cell(let c):
            // One card from a column into an empty cell; never cell to cell.
            guard state.cells.indices.contains(c), state.cells[c] == nil, run.count == 1 else { return false }
            if case .tableau = move.source { return true }
            return false

        case .foundation(let f):
            guard (0..<4).contains(f), run.count == 1 else { return false }
            return canPlaceOnFoundation(first, state.foundations[f])

        case .tableau(let t):
            guard (0..<8).contains(t), run.count <= maxRun(onto: .tableau(t), in: state) else { return false }
            guard let top = state.tableau[t].last else { return true }
            return first.rank == top.rank - 1 && first.suit.isRed != top.suit.isRed
        }
    }

    /// Applies a legal move as the player's: it counts as one move, however many cards it carries.
    public static func apply(_ move: Move, to state: inout GameState) {
        applyAutomatic(move, to: &state)
        state.moveCount += 1
    }

    /// Applies a legal move the game makes by itself — an automatic play home, or a Finish step:
    /// it costs no move.
    public static func applyAutomatic(_ move: Move, to state: inout GameState) {
        precondition(canMove(move, in: state), "apply called with an illegal move: \(move)")
        let run = Array(state[move.source][move.index...])
        state[move.source].removeSubrange(move.index...)
        state[move.destination].append(contentsOf: run)
        state.isWon = isWon(state)
    }

    /// The longest run that may move onto `destination` at once: the cards the free spaces could
    /// carry one by one — (empty free cells + 1) × 2^(empty columns), the empty columns counted
    /// without the destination.
    public static func maxRun(onto destination: PileID, in state: GameState) -> Int {
        var emptyColumns = state.emptyColumns
        if case .tableau(let t) = destination, state.tableau.indices.contains(t), state.tableau[t].isEmpty {
            emptyColumns -= 1
        }
        return (state.emptyCells + 1) << max(emptyColumns, 0)
    }

    /// Whether the card at `index` in `source` may be picked up (dragged): a free cell's card, or a
    /// column card with an ordered run below it. Never a foundation card, and nothing once won.
    /// (A run too long for the free spaces may be lifted; the drop is refused.)
    public static func canPickUp(from source: PileID, index: Int, in state: GameState) -> Bool {
        !state.isWon && movableRun(from: source, index: index, in: state) != nil
    }

    // MARK: Tap-to-move

    /// Where a tap on the card at `index` in `source` sends it (with the run below it), or nil.
    ///
    /// In order: its foundation, if it is one card; a column that accepts it, scanning left to right
    /// from the column after its own; a free cell, if it is one card from a column; an empty column —
    /// never for a card already alone in its column, which would change nothing. Cards on a
    /// foundation never move.
    public static func autoDestination(for source: PileID, index: Int, in state: GameState) -> PileID? {
        guard !state.isWon, let run = movableRun(from: source, index: index, in: state) else { return nil }
        let legal = { (to: PileID) in canMove(Move(source: source, index: index, destination: to), in: state) }

        if run.count == 1, let f = (0..<4).first(where: { legal(.foundation($0)) }) {
            return .foundation(f)
        }
        let start: Int
        if case .tableau(let s) = source { start = s + 1 } else { start = 0 }
        let order = (0..<8).map { (start + $0) % 8 }
        if let t = order.first(where: { !state.tableau[$0].isEmpty && legal(.tableau($0)) }) {
            return .tableau(t)
        }
        if let c = state.cells.indices.first(where: { legal(.cell($0)) }) {
            return .cell(c)
        }
        if case .tableau = source, index == 0 { return nil }
        if let t = order.first(where: { state.tableau[$0].isEmpty && legal(.tableau($0)) }) {
            return .tableau(t)
        }
        return nil
    }

    // MARK: Automatic plays home

    /// Whether no other card could still need `card`: an ace or a two always; any other card once
    /// both foundations of the other colour have reached at least one rank lower.
    public static func isSafeToPlayHome(_ card: Card, in state: GameState) -> Bool {
        if card.rank <= 2 { return true }
        let others = Suit.allCases.filter { $0.isRed != card.suit.isRed }
        return others.allSatisfy { foundationRank(of: $0, in: state) >= card.rank - 1 }
    }

    /// The next automatic play: a safe card from a free cell or the end of a column that can go
    /// home now (free cells first, then columns left to right), or nil.
    public static func nextSafePlay(in state: GameState) -> Move? {
        guard !state.isWon else { return nil }
        let sources: [PileID] = state.cells.indices.map { .cell($0) } + (0..<8).map { .tableau($0) }
        for source in sources {
            guard let card = state[source].last, isSafeToPlayHome(card, in: state) else { continue }
            let index = state[source].count - 1
            if let f = (0..<4).first(where: { canMove(Move(source: source, index: index, destination: .foundation($0)), in: state) }) {
                return Move(source: source, index: index, destination: .foundation(f))
            }
        }
        return nil
    }

    /// Every automatic play, one after another, until none is left. Returns the moves made.
    @discardableResult
    public static func settle(_ state: inout GameState) -> [Move] {
        var made: [Move] = []
        while let move = nextSafePlay(in: state) {
            applyAutomatic(move, to: &state)
            made.append(move)
        }
        return made
    }

    // MARK: Finish and winning

    /// Offered once every column is in order — each card lower than the one above it — so every
    /// remaining card can go home without help.
    public static func canAutoFinish(_ state: GameState) -> Bool {
        !state.isWon && state.tableau.allSatisfy { column in
            zip(column, column.dropFirst()).allSatisfy { upper, lower in lower.rank < upper.rank }
        }
    }

    /// The next Finish step: the lowest card that can go to a foundation now, from a free cell or
    /// the end of a column (cells first, then columns left to right, on a tie), or nil.
    public static func nextAutoFinishMove(in state: GameState) -> Move? {
        guard !state.isWon else { return nil }
        var best: (move: Move, rank: Int)?
        let sources: [PileID] = state.cells.indices.map { .cell($0) } + (0..<8).map { .tableau($0) }
        for source in sources {
            guard let card = state[source].last, best == nil || card.rank < best!.rank else { continue }
            let index = state[source].count - 1
            if let f = (0..<4).first(where: { canMove(Move(source: source, index: index, destination: .foundation($0)), in: state) }) {
                best = (Move(source: source, index: index, destination: .foundation(f)), card.rank)
            }
        }
        return best?.move
    }

    public static func isWon(_ state: GameState) -> Bool {
        state.foundations.count == 4 && state.foundations.allSatisfy { $0.count == 13 }
    }

    // MARK: Helpers

    /// The cards that would move if `index` in `source` were picked up — a slice, so it keeps the
    /// pile's indices (use `first`, never `[0]`) — or nil: a free cell's card, or a column card
    /// with the cards below it in order (each one rank lower and the other colour). Never a
    /// foundation card.
    static func movableRun(from source: PileID, index: Int, in state: GameState) -> ArraySlice<Card>? {
        switch source {
        case .foundation:
            return nil
        case .cell(let c):
            guard state.cells.indices.contains(c), index == 0, state.cells[c] != nil else { return nil }
        case .tableau(let t):
            guard (0..<8).contains(t), state.tableau[t].indices.contains(index) else { return nil }
        }
        let run = state[source][index...]
        for (upper, lower) in zip(run, run.dropFirst())
        where lower.rank != upper.rank - 1 || lower.suit.isRed == upper.suit.isRed {
            return nil
        }
        return run
    }

    static func canPlaceOnFoundation(_ card: Card, _ foundation: [Card]) -> Bool {
        guard let top = foundation.last else { return card.rank == 1 }
        return card.suit == top.suit && card.rank == top.rank + 1
    }

    /// How far a suit's foundation has reached: 0 before its ace.
    static func foundationRank(of suit: Suit, in state: GameState) -> Int {
        state.foundations.first { $0.first?.suit == suit }?.count ?? 0
    }
}
