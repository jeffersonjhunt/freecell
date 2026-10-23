import Foundation

/// Every pile is ordered bottom to top: `last` is the playable card, and a run to move is
/// `pile[index...]`. FreeCell deals every card face up, so a card has no face-down state.

public enum Suit: Int, Codable, CaseIterable, Sendable {
    case clubs, diamonds, hearts, spades          // Microsoft's deck order

    public var isRed: Bool { self == .hearts || self == .diamonds }
}

public struct Card: Identifiable, Hashable, Codable, Sendable {
    public let suit: Suit
    public let rank: Int          // 1...13, ace low

    /// Stable 0...51, derived from suit and rank, so views track the same card across piles.
    public var id: Int { suit.rawValue * 13 + rank - 1 }

    public init(suit: Suit, rank: Int) {
        self.suit = suit
        self.rank = rank
    }
}

public enum PileID: Hashable, Codable, Sendable {
    case cell(Int)         // 0...3 (0...1 in Hard Core)
    case foundation(Int)   // 0...3
    case tableau(Int)      // 0...7
}

public struct Move: Hashable, Codable, Sendable {
    public let source: PileID
    public let index: Int         // first card moved, within the source pile (0 for a cell)
    public let destination: PileID

    public init(source: PileID, index: Int, destination: PileID) {
        self.source = source
        self.index = index
        self.destination = destination
    }
}

/// The whole game: rendering, saving and testing all read from it.
public struct GameState: Codable, Sendable, Equatable {
    public var cells: [Card?]         // 4, or 2 in Hard Core
    public var foundations: [[Card]]  // always 4
    public var tableau: [[Card]]      // always 8
    /// The game number, 1...1_000_000: Microsoft's numbering, which alone decides the deal.
    public var number: Int
    /// Hard Core: two free cells instead of four (spec "Hard Core").
    public var isHardCore: Bool
    /// Relaxed: any ordered run moves at once, whatever the free spaces (spec "Relaxed").
    public var isRelaxed: Bool
    public var moveCount: Int
    public var elapsed: TimeInterval
    public var isWon: Bool
    /// Undos taken in this game. Undo itself never takes this back.
    public var undos: Int
    /// This game played again from the start (Restart): its win is never recorded.
    public var isRestarted: Bool

    public init(cells: [Card?], foundations: [[Card]], tableau: [[Card]], number: Int,
                isHardCore: Bool = false, isRelaxed: Bool = false, moveCount: Int = 0,
                elapsed: TimeInterval = 0, isWon: Bool = false, undos: Int = 0, isRestarted: Bool = false) {
        self.cells = cells
        self.foundations = foundations
        self.tableau = tableau
        self.number = number
        self.isHardCore = isHardCore
        self.isRelaxed = isRelaxed
        self.moveCount = moveCount
        self.elapsed = elapsed
        self.isWon = isWon
        self.undos = undos
        self.isRestarted = isRestarted
    }

    /// Decodes a saved game. Saves from before Relaxed (the first TestFlight build) are standard games.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cells = try c.decode([Card?].self, forKey: .cells)
        foundations = try c.decode([[Card]].self, forKey: .foundations)
        tableau = try c.decode([[Card]].self, forKey: .tableau)
        number = try c.decode(Int.self, forKey: .number)
        isHardCore = try c.decode(Bool.self, forKey: .isHardCore)
        isRelaxed = try c.decodeIfPresent(Bool.self, forKey: .isRelaxed) ?? false
        moveCount = try c.decode(Int.self, forKey: .moveCount)
        elapsed = try c.decode(TimeInterval.self, forKey: .elapsed)
        isWon = try c.decode(Bool.self, forKey: .isWon)
        undos = try c.decode(Int.self, forKey: .undos)
        isRestarted = try c.decode(Bool.self, forKey: .isRestarted)
    }

    /// Free cells with no card in them.
    public var emptyCells: Int { cells.filter { $0 == nil }.count }
    /// Columns with no card in them.
    public var emptyColumns: Int { tableau.filter(\.isEmpty).count }

    /// The cards of any pile, bottom to top; a free cell holds none or one.
    public subscript(pile: PileID) -> [Card] {
        get {
            switch pile {
            case .cell(let i): cells[i].map { [$0] } ?? []
            case .foundation(let i): foundations[i]
            case .tableau(let i): tableau[i]
            }
        }
        set {
            switch pile {
            case .cell(let i):
                precondition(newValue.count <= 1, "a free cell holds one card")
                cells[i] = newValue.first
            case .foundation(let i): foundations[i] = newValue
            case .tableau(let i): tableau[i] = newValue
            }
        }
    }
}
