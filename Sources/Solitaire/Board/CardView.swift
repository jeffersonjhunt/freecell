import SwiftUI
import SolitaireEngine

/// One card, drawn in SwiftUI (no images), in the face and back of the environment's `cardStyle`
/// (spec "Card styles"): a rounded rectangle with a hairline border and a 1 pt shadow, the corner
/// index top-left, a large suit below it; a back is a patterned panel inset in the card. Flipping
/// rotates about the Y axis; faces never invert in dark mode.
struct CardView: View {
    let card: Card
    let width: CGFloat
    var isHighlighted = false
    /// False for cards buried in a stacked pile (stock, waste, foundation): only the top card casts
    /// a shadow, or 20 stacked shadows add up to a dark smear.
    var hasShadow = true
    /// Being dragged: a slightly stronger shadow lifts it above the board.
    var isLifted = false

    var body: some View {
        FlippingCard(angle: card.isFaceUp ? 0 : 180, card: card, width: width, hasShadow: hasShadow)
            .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: isLifted ? 5 : 0, y: isLifted ? 3 : 0)
            .frame(width: width, height: width * BoardMetrics.aspect)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: width * 0.09).strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(card.isFaceUp ? Self.spokenName(card) : "Face-down card")
    }

    nonisolated static func rankText(_ rank: Int) -> String {
        [1: "A", 11: "J", 12: "Q", 13: "K"][rank] ?? "\(rank)"
    }

    nonisolated static func suitSymbol(_ suit: Suit) -> String {
        ["♠", "♥", "♦", "♣"][suit.rawValue]
    }

    nonisolated static func spokenName(_ card: Card) -> String {
        let rank = [1: "Ace", 11: "Jack", 12: "Queen", 13: "King"][card.rank] ?? "\(card.rank)"
        return "\(rank) of \(["Spades", "Hearts", "Diamonds", "Clubs"][card.suit.rawValue])"
    }
}

/// Rotates about the Y axis and shows the side facing the viewer: the face below 90°, the back
/// (unmirrored) from 90° on — so mid-flip never shows both sides at once.
private struct FlippingCard: View, Animatable {
    var angle: Double
    let card: Card
    let width: CGFloat
    let hasShadow: Bool

    /// Nonisolated: `Animatable` is not main-actor isolated, and this is only a stored Double.
    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        Group {
            if angle < 90 {
                CardFace(card: card, width: width, hasShadow: hasShadow)
            } else {
                CardBack(width: width, hasShadow: hasShadow)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

private struct CardFace: View {
    let card: Card
    let width: CGFloat
    let hasShadow: Bool
    @Environment(\.cardStyle) private var style

    var body: some View {
        let spec = FaceSpec.of(style.face)
        let shape = RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
        let ink = card.suit.isRed ? spec.red : spec.black
        let cap = width * spec.capHeight
        shape
            .fill(spec.paper)
            .overlay {
                if let frame = spec.frame {
                    RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                        .strokeBorder(frame, lineWidth: max(width * 0.012, 0.5))
                        .padding(width * 0.05)
                }
            }
            .overlay(shape.strokeBorder(spec.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(hasShadow ? 0.3 : 0), radius: 1, y: 1)
            .overlay(alignment: .topLeading) {
                HStack(alignment: .firstTextBaseline, spacing: width * 0.01) {
                    Text(CardView.rankText(card.rank))
                        .font(.system(size: width * spec.rankSize, weight: spec.rankWeight, design: spec.rankDesign))
                    Text(CardView.suitSymbol(card.suit))
                        .font(.system(size: width * spec.suitSize))
                }
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                // Placed by its capitals, not its line box: the caps' tops sit `indexTop` below the
                // edge, so the index fits the narrowest fanned strip (decision D1).
                .alignmentGuide(.top) { d in d[.firstTextBaseline] - cap }
                .offset(x: width * FaceSpec.indexLeading, y: width * FaceSpec.indexTop)
            }
            .overlay(alignment: spec.pip == .corner ? .bottomTrailing : .center) {
                Text(CardView.suitSymbol(card.suit))
                    .font(.system(size: width * spec.pipSize))
                    .foregroundStyle(ink)
                    .padding(.trailing, spec.pip == .corner ? width * 0.06 : 0)
                    .padding(.bottom, spec.pip == .corner ? width * 0.01 : 0)
                    .offset(y: spec.pip == .center ? width * 0.12 : 0)
            }
            .environment(\.colorScheme, .light)
    }
}

private struct CardBack: View {
    let width: CGFloat
    let hasShadow: Bool
    @Environment(\.cardStyle) private var style

    var body: some View {
        let spec = BackSpec.of(style.back)
        let radius = width * 0.09
        let inset = width * 0.07
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let panel = RoundedRectangle(cornerRadius: max(radius - inset, 1), style: .continuous)
        shape
            .fill(spec.paper)
            .overlay {
                panel
                    .fill(spec.panel)
                    .overlay { pattern(spec) }
                    .overlay {
                        if let frame = spec.frame {
                            RoundedRectangle(cornerRadius: max(radius - inset - width * 0.035, 1), style: .continuous)
                                .strokeBorder(frame, lineWidth: max(width * 0.015, 0.5))
                                .padding(width * 0.035)
                        }
                    }
                    .clipShape(panel)
                    .padding(inset)
            }
            .overlay(shape.strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(hasShadow ? 0.3 : 0), radius: 1, y: 1)
    }

    @ViewBuilder
    private func pattern(_ spec: BackSpec) -> some View {
        switch spec.pattern {
        case .lattice:
            DiagonalPattern(spacing: width * 0.1)
                .stroke(spec.ink, lineWidth: max(width * 0.02, 0.5))
        case .diamonds:
            DiamondGrid(spacing: width * 0.1).fill(spec.ink)
        case .rays:
            SunRays().fill(spec.ink)
        }
    }
}

/// Small diamonds on a staggered grid, filling the rect.
private struct DiamondGrid: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = max(spacing, 3)
        let r = s * 0.28
        var row = 0
        var y = rect.minY
        while y <= rect.maxY + s {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : s / 2)
            while x <= rect.maxX + s {
                p.move(to: CGPoint(x: x, y: y - r))
                p.addLine(to: CGPoint(x: x + r, y: y))
                p.addLine(to: CGPoint(x: x, y: y + r))
                p.addLine(to: CGPoint(x: x - r, y: y))
                p.closeSubpath()
                x += s
            }
            y += s / 2
            row += 1
        }
        return p
    }
}

/// Rays fanning up from the middle of the bottom edge: 4° wide, every 12°, from the left
/// horizontal round to the right, reaching past the rect's corners.
private struct SunRays: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let centre = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = hypot(rect.width, rect.height)
        var angle = 180.0
        while angle < 360 {
            p.move(to: centre)
            p.addArc(center: centre, radius: radius, startAngle: .degrees(angle),
                     endAngle: .degrees(angle + 4), clockwise: false)
            p.closeSubpath()
            angle += 12
        }
        return p
    }
}

/// Repeating diagonal lines, both directions, filling the rect.
private struct DiagonalPattern: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = max(spacing, 2)
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += step
        }
        return p
    }
}

/// An empty pile's outline on the table.
struct PileOutline: View {
    let width: CGFloat
    var symbol: String?

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            .background(RoundedRectangle(cornerRadius: width * 0.09).fill(Color.black.opacity(0.08)))
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: width * 0.35))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .frame(width: width, height: width * BoardMetrics.aspect)
    }
}
