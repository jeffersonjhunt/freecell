import CoreGraphics
import SwiftUI
import FreeCellEngine

/// Where every card sits for a given state and metrics. All 52 cards are always placed, so a
/// card moving between piles is the same view animating to a new frame.
struct CardPlacement: Identifiable, Equatable {
    let card: Card
    let pile: PileID
    let index: Int
    let frame: CGRect
    let zIndex: Double
    /// Whether the card shows more than an edge: the last card of any pile, and every card of a
    /// column (each shows its corner index).
    let isExposed: Bool
    var id: Int { card.id }
    var isOnFoundation: Bool { if case .foundation = pile { true } else { false } }
}

struct BoardLayout: Equatable {
    let metrics: BoardMetrics
    let placements: [CardPlacement]
    /// The free cells this game has: four, or two in Hard Core (the other slots are drawn closed).
    let cellCount: Int

    /// The empty-pile outline and drop target for every pile (spec "Top row": free cells in
    /// columns 1–4, foundations in 5–8).
    func slot(_ pile: PileID) -> CGRect {
        let m = metrics
        let size = CGSize(width: m.cardWidth, height: m.cardHeight)
        switch pile {
        case .cell(let c): return CGRect(origin: CGPoint(x: m.columnX(c), y: m.topRowY), size: size)
        case .foundation(let f): return CGRect(origin: CGPoint(x: m.columnX(4 + f), y: m.topRowY), size: size)
        case .tableau(let t): return CGRect(origin: CGPoint(x: m.columnX(t), y: m.tableauY), size: size)
        }
    }

    /// The area a pile occupies: its slot, and for a column everything down to its last card.
    func frame(of pile: PileID) -> CGRect {
        placements.filter { $0.pile == pile }.reduce(slot(pile)) { $0.union($1.frame) }
    }

    /// Every pile a card can be dropped on: the open free cells, the foundations and the columns.
    var dropPiles: [PileID] {
        (0..<cellCount).map { .cell($0) } + (0..<4).map { .foundation($0) } + (0..<8).map { .tableau($0) }
    }

    /// Where a drag lands when released with the dragged card's centre at `point`: the pile whose
    /// frame is nearest that point (distance 0 inside it; the first listed on a tie). That may be
    /// the pile it came from — a drop there is illegal, so the card springs back rather than
    /// jumping somewhere else. Whether the move is legal is the store's call.
    func dropTarget(for point: CGPoint) -> PileID? {
        dropPiles.min { a, b in Self.distance(point, frame(of: a)) < Self.distance(point, frame(of: b)) }
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// - Parameter raised: the cards currently moving. Every pile that received one is drawn above
    ///   the rest, so a card travelling to another pile never passes under a deeper column. Whole
    ///   piles are raised, not single cards, so the order within a pile never changes.
    init(state: GameState, metrics m: BoardMetrics, raised: Set<Int> = []) {
        self.metrics = m
        self.cellCount = state.cells.count
        var out: [CardPlacement] = []
        func isRaised(_ cards: [Card]) -> Bool { cards.contains { raised.contains($0.id) } }
        func stack(_ cards: [Card], _ pile: PileID, _ origin: CGPoint, z: Double, fan: CGFloat = 0) {
            let base = isRaised(cards) ? 1000 + z : z
            for (i, card) in cards.enumerated() {
                out.append(CardPlacement(
                    card: card, pile: pile, index: i,
                    frame: CGRect(x: origin.x, y: origin.y + CGFloat(i) * fan,
                                  width: m.cardWidth, height: m.cardHeight),
                    zIndex: base + Double(i),
                    isExposed: fan > 0 || i == cards.count - 1))
            }
        }
        let empty = BoardLayout(metrics: m, placements: [], cellCount: state.cells.count)
        for (c, card) in state.cells.enumerated() {
            stack(card.map { [$0] } ?? [], .cell(c), empty.slot(.cell(c)).origin, z: 100)
        }
        for f in 0..<4 {
            stack(state.foundations[f], .foundation(f), empty.slot(.foundation(f)).origin, z: 200)
        }
        for t in 0..<8 {
            let column = state.tableau[t]
            stack(column, .tableau(t), empty.slot(.tableau(t)).origin, z: 300, fan: m.fan(forColumnOf: column.count))
        }
        self.placements = out
    }

    private init(metrics: BoardMetrics, placements: [CardPlacement], cellCount: Int) {
        self.metrics = metrics
        self.placements = placements
        self.cellCount = cellCount
    }
}

/// What VoiceOver gets for a card (spec: every card is named by rank, suit and place). Buried
/// foundation cards are hidden, so a swipe reads one card per foundation; every column card is
/// read, since all are face up. A card is a button when a tap would move it.
enum CardAccessibility: Equatable {
    case hidden
    case label(String)
    case button(String)

    static func of(_ p: CardPlacement, in state: GameState) -> CardAccessibility {
        let name = CardView.spokenName(p.card)
        switch p.pile {
        case .cell(let c):
            let spoken = "\(name), free cell \(c + 1)"
            return tappable(p, state) ? .button(spoken) : .label(spoken)
        case .foundation(let f):
            guard p.index == state.foundations[f].count - 1 else { return .hidden }
            return .label("\(name), foundation \(f + 1)")      // taps on foundations do nothing
        case .tableau(let t):
            let spoken = "\(name), column \(t + 1)"
            return tappable(p, state) ? .button(spoken) : .label(spoken)
        }
    }

    private static func tappable(_ p: CardPlacement, _ state: GameState) -> Bool {
        FreeCellEngine.autoDestination(for: p.pile, index: p.index, in: state) != nil
    }
}
