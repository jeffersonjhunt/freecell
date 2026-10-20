import CoreGraphics
import SwiftUI
import SolitaireEngine

/// Where every card sits for a given state and metrics. All 52 cards are always placed, so a
/// card moving between piles is the same view animating to a new frame.
struct CardPlacement: Identifiable, Equatable {
    let card: Card
    let pile: PileID
    let index: Int
    let frame: CGRect
    let zIndex: Double
    /// Whether the card is visible edge-on rather than buried under the card above it.
    let isExposed: Bool
    var id: Int { card.id }
    var isOnFoundation: Bool { if case .foundation = pile { true } else { false } }
}

/// Which end of the top row the stock and waste sit at (spec "Top row"; a setting, left by
/// default). On the right the row is mirrored: foundations in columns 0–3, waste 5, stock 6.
enum DrawPileSide: String, CaseIterable, Sendable {
    case left, right
}

extension EnvironmentValues {
    /// The board lays out its top row for this side; the app sets it from the saved setting.
    @Entry var drawPileSide = DrawPileSide.left
}

struct BoardLayout: Equatable {
    let metrics: BoardMetrics
    let placements: [CardPlacement]
    let side: DrawPileSide

    /// The empty-pile outline and drop target for every pile.
    func slot(_ pile: PileID) -> CGRect {
        let m = metrics
        let size = CGSize(width: m.cardWidth, height: m.cardHeight)
        let right = side == .right
        switch pile {
        case .stock: return CGRect(origin: CGPoint(x: m.columnX(right ? 6 : 0), y: m.topRowY), size: size)
        case .waste: return CGRect(origin: CGPoint(x: m.columnX(right ? 5 : 1), y: m.topRowY), size: size)
        case .foundation(let f):
            return CGRect(origin: CGPoint(x: m.columnX(right ? f : 3 + f), y: m.topRowY), size: size)
        case .tableau(let t): return CGRect(origin: CGPoint(x: m.columnX(t), y: m.tableauY), size: size)
        }
    }

    /// The area a pile occupies: its slot, and for a column everything down to its last card.
    func frame(of pile: PileID) -> CGRect {
        placements.filter { $0.pile == pile }.reduce(slot(pile)) { $0.union($1.frame) }
    }

    /// Where a drag lands when released with the dragged card's centre at `point`: the foundation or
    /// column whose frame is nearest that point (distance 0 inside it; leftmost on a tie). That may
    /// be the pile it came from — a drop there is illegal, so the card springs back rather than
    /// jumping to some other pile. Whether the move is legal is the store's call.
    func dropTarget(for point: CGPoint) -> PileID? {
        let piles: [PileID] = (0..<4).map { .foundation($0) } + (0..<7).map { .tableau($0) }
        return piles.min { a, b in
            Self.distance(point, frame(of: a)) < Self.distance(point, frame(of: b))
        }
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// - Parameter raised: the cards currently moving. Every pile that received one is drawn above
    ///   the rest, so a card travelling to another pile never passes under a deeper column. Whole
    ///   piles are raised, not single cards, so the order within a pile never changes (a new deal
    ///   leaves some cards in the same pile; raising only the others would bury them mid-pile).
    init(state: GameState, metrics m: BoardMetrics, raised: Set<Int> = [], side: DrawPileSide = .left) {
        self.metrics = m
        self.side = side
        var out: [CardPlacement] = []
        func isRaised(_ cards: [Card]) -> Bool { cards.contains { raised.contains($0.id) } }
        func stack(_ cards: [Card], _ pile: PileID, _ origin: CGPoint, z: Double,
                   exposedFrom: Int? = nil, offset: (Int) -> CGSize = { _ in .zero }) {
            let firstExposed = exposedFrom ?? max(cards.count - 1, 0)
            let base = isRaised(cards) ? 1000 + z : z
            for (i, card) in cards.enumerated() {
                let o = offset(i)
                out.append(CardPlacement(
                    card: card, pile: pile, index: i,
                    frame: CGRect(x: origin.x + o.width, y: origin.y + o.height,
                                  width: m.cardWidth, height: m.cardHeight),
                    zIndex: base + Double(i),
                    isExposed: i >= firstExposed))
            }
        }
        let empty = BoardLayout(metrics: m, placements: [], side: side)
        stack(state.stock, .stock, empty.slot(.stock).origin, z: 0)
        // Draw 3 fans the top three waste cards into the empty column beside the waste, each card
        // 0.3 × width from the next, so the two beneath the playable top card show their corner
        // index at their left edge. With the draw pile on the left the fan opens rightwards from
        // the waste's slot (the top card furthest right); on the right the top card stays on the
        // slot, next to the stock, and the two beneath it step leftwards. Buried cards sit under
        // the bottom of the fan.
        let fanned = state.drawCount == 3 ? 3 : 1
        let firstFanned = max(state.waste.count - fanned, 0)
        let lastIndex = state.waste.count - 1
        stack(state.waste, .waste, empty.slot(.waste).origin, z: 100, exposedFrom: firstFanned) { i in
            let step = m.cardWidth * 0.3
            let k = CGFloat(max(i, firstFanned))
            return side == .left
                ? CGSize(width: (k - CGFloat(firstFanned)) * step, height: 0)
                : CGSize(width: -(CGFloat(lastIndex) - k) * step, height: 0)
        }
        for f in 0..<4 {
            stack(state.foundations[f], .foundation(f), empty.slot(.foundation(f)).origin, z: 200)
        }
        for t in 0..<7 {
            let column = state.tableau[t]
            let down = column.dropLast().filter { !$0.isFaceUp }.count
            let up = max(column.count - 1 - down, 0)
            let fans = m.fans(faceDown: down, faceUp: up)
            var y: CGFloat = 0
            var offsets: [CGFloat] = []
            for card in column {
                offsets.append(y)
                y += card.isFaceUp ? fans.up : fans.down
            }
            stack(column, .tableau(t), empty.slot(.tableau(t)).origin, z: 300, exposedFrom: 0) { i in
                CGSize(width: 0, height: offsets[i])
            }
        }
        self.placements = out
    }

    private init(metrics: BoardMetrics, placements: [CardPlacement], side: DrawPileSide) {
        self.metrics = metrics
        self.placements = placements
        self.side = side
    }
}

/// What VoiceOver gets for a card (spec: every card is named by rank and suit, every empty pile by
/// name). Buried cards — under the top of the stock, waste or a foundation — are hidden so a swipe
/// doesn't read 24 face-down stock cards; the stock is one "Stock, N cards" element on its outline.
enum CardAccessibility: Equatable {
    case hidden
    case label(String)
    case button(String)

    static func of(_ p: CardPlacement, in state: GameState) -> CardAccessibility {
        let name = CardView.spokenName(p.card)
        switch p.pile {
        case .stock:
            return .hidden
        case .waste:
            guard p.isExposed else { return .hidden }
            let isTop = p.index == state.waste.count - 1
            return isTop && tappable(p, state) ? .button("\(name), waste") : .label("\(name), waste")
        case .foundation(let f):
            guard p.index == state.foundations[f].count - 1 else { return .hidden }
            return .label("\(name), foundation \(f + 1)")      // taps on foundations do nothing
        case .tableau(let t):
            guard p.card.isFaceUp else { return .hidden }
            var spoken = "\(name), column \(t + 1)"
            let hiddenBelow = state.tableau[t][..<p.index].filter { !$0.isFaceUp }.count
            if hiddenBelow > 0, p.index == hiddenBelow {           // the first face-up card says it
                spoken += ", \(hiddenBelow) face-down \(hiddenBelow == 1 ? "card" : "cards") under it"
            }
            return tappable(p, state) ? .button(spoken) : .label(spoken)
        }
    }

    private static func tappable(_ p: CardPlacement, _ state: GameState) -> Bool {
        SolitaireEngine.autoDestination(for: p.pile, index: p.index, in: state) != nil
    }
}
