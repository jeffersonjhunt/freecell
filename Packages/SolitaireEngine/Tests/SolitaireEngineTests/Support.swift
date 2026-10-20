@testable import SolitaireEngine

/// "AS", "10H", "KD" → a face-up card; `down("3C")` → face down.
func up(_ code: String) -> Card { parse(code, faceUp: true) }
func down(_ code: String) -> Card { parse(code, faceUp: false) }

private func parse(_ code: String, faceUp: Bool) -> Card {
    let suitChar = code.last!
    let rankText = String(code.dropLast())
    let rank = ["A": 1, "J": 11, "Q": 12, "K": 13][rankText] ?? Int(rankText)!
    let suit: Suit = ["S": .spades, "H": .hearts, "D": .diamonds, "C": .clubs][suitChar]!
    return Card(suit: suit, rank: rank, isFaceUp: faceUp)
}

/// A hand-built position; unspecified piles are empty.
func board(tableau: [[Card]] = [], waste: [Card] = [], stock: [Card] = [],
           foundations: [[Card]] = [], drawCount: Int = 1) -> GameState {
    GameState(stock: stock, waste: waste,
              foundations: foundations + Array(repeating: [], count: 4 - foundations.count),
              tableau: tableau + Array(repeating: [], count: 7 - tableau.count),
              drawCount: drawCount)
}

/// A foundation holding ace...rank of a suit.
func foundation(_ suit: Suit, upTo rank: Int) -> [Card] {
    (1...rank).map { Card(suit: suit, rank: $0, isFaceUp: true) }
}

func allCards(_ s: GameState) -> [Card] {
    s.stock + s.waste + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
}

/// Every move the rules allow in `s` (excluding the stock tap).
func legalMoves(_ s: GameState) -> [Move] {
    var sources: [(PileID, Int)] = []
    if !s.waste.isEmpty { sources.append((.waste, s.waste.count - 1)) }
    for f in 0..<4 where !s.foundations[f].isEmpty { sources.append((.foundation(f), s.foundations[f].count - 1)) }
    for t in 0..<7 { for i in s.tableau[t].indices { sources.append((.tableau(t), i)) } }
    let destinations: [PileID] = (0..<4).map { .foundation($0) } + (0..<7).map { .tableau($0) }
    return sources.flatMap { src, i in
        destinations.map { Move(source: src, index: i, destination: $0) }
    }.filter { SolitaireEngine.canMove($0, in: s) }
}

/// A simple deterministic player, good enough to find winnable deals: foundation moves first,
/// then tableau moves that uncover a card, then waste plays, then the stock. Gives up after
/// three passes through the stock without progress. Returns the final state.
func playGreedily(_ start: GameState, stepLimit: Int = 5000) -> GameState {
    var s = start
    var idleRedeals = 0
    for _ in 0..<stepLimit {
        if s.isWon { break }
        if SolitaireEngine.canAutoFinish(s), let m = SolitaireEngine.nextAutoFinishMove(in: s) {
            SolitaireEngine.apply(m, to: &s); continue
        }
        let moves = legalMoves(s)
        let toFoundation = moves.first {
            if case .foundation = $0.destination { return true } else { return false }
        }
        let uncovering = moves.first { m in
            guard case .tableau(let t) = m.source, case .tableau = m.destination else { return false }
            return m.index > 0 && !s.tableau[t][m.index - 1].isFaceUp
        }
        let fromWaste = moves.first { m in
            if case .waste = m.source, case .tableau = m.destination { return true } else { return false }
        }
        if let m = toFoundation ?? uncovering ?? fromWaste {
            SolitaireEngine.apply(m, to: &s)
            idleRedeals = 0
            continue
        }
        if s.stock.isEmpty {
            if s.waste.isEmpty || idleRedeals >= 3 { break }
            idleRedeals += 1
        }
        SolitaireEngine.drawFromStock(&s)
    }
    return s
}
