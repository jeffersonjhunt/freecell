@testable import FreeCellEngine

typealias E = FreeCellEngine

/// "AS", "10H" or "TH", "KD" → a card.
func c(_ code: String) -> Card {
    let suit: Suit = ["C": .clubs, "D": .diamonds, "H": .hearts, "S": .spades][code.last!]!
    let rankText = String(code.dropLast())
    let rank = ["A": 1, "T": 10, "J": 11, "Q": 12, "K": 13][rankText] ?? Int(rankText)!
    return Card(suit: suit, rank: rank)
}

/// "JD 2D 9H" → cards.
func cards(_ codes: String) -> [Card] { codes.split(separator: " ").map { c(String($0)) } }

/// A card's two-character name as the published deals write it: "TC", "AH".
func name(_ card: Card) -> String {
    let ranks = Array("A23456789TJQK")
    return "\(ranks[card.rank - 1])\(["C", "D", "H", "S"][card.suit.rawValue])"
}

/// A hand-built position; unspecified piles are empty.
func board(columns: [[Card]] = [], cells: [Card?] = [], foundations: [[Card]] = [],
           hardCore: Bool = false, number: Int = 1) -> GameState {
    let cellCount = E.cellCount(hardCore: hardCore)
    return GameState(cells: cells + Array(repeating: nil, count: cellCount - cells.count),
                     foundations: foundations + Array(repeating: [], count: 4 - foundations.count),
                     tableau: columns + Array(repeating: [], count: 8 - columns.count),
                     number: number, isHardCore: hardCore)
}

/// A foundation holding ace…rank of a suit.
func foundation(_ suit: Suit, upTo rank: Int) -> [Card] {
    rank == 0 ? [] : (1...rank).map { Card(suit: suit, rank: $0) }
}

func allCards(_ s: GameState) -> [Card] {
    s.cells.compactMap { $0 } + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
}

/// Every move the rules allow in `s`.
func legalMoves(_ s: GameState) -> [Move] {
    var sources: [(PileID, Int)] = s.cells.indices.map { (.cell($0), 0) }
    for t in 0..<8 { for i in s.tableau[t].indices { sources.append((.tableau(t), i)) } }
    let destinations: [PileID] = s.cells.indices.map { .cell($0) } + (0..<4).map { .foundation($0) }
        + (0..<8).map { .tableau($0) }
    return sources.flatMap { src, i in destinations.map { Move(source: src, index: i, destination: $0) } }
        .filter { E.canMove($0, in: s) }
}

/// A repeatable generator for tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
