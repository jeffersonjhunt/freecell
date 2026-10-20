import SolitaireEngine
import SwiftUI

/// The win animation the player chose (spec "Win animations"): Cascade (the default), Rainfall,
/// Decay or Shuffle; Random picks one of those four per game; None plays nothing. Reduce Motion
/// always means none.
enum WinAnimation: String, CaseIterable, Identifiable, Sendable {
    case cascade, rainfall, decay, shuffle, random, none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cascade: "Cascade"
        case .rainfall: "Rainfall"
        case .decay: "Decay"
        case .shuffle: "Shuffle"
        case .random: "Random"
        case .none: "None"
        }
    }

    static let playable: [WinAnimation] = [.cascade, .rainfall, .decay, .shuffle]

    /// What plays for the game dealt from `seed`: nil for None; Random settles on one of the four,
    /// the same one for that game every time it is asked.
    func resolved(seed: UInt64) -> WinAnimation? {
        switch self {
        case .none: nil
        case .random: Self.playable[Int(seed % UInt64(Self.playable.count))]
        default: self
        }
    }
}

extension EnvironmentValues {
    /// The win animation for the game on the board, already resolved (nil: none plays).
    @Entry var winAnimation: WinAnimation? = .cascade
}

/// Draws the chosen animation over the board once the game is won; `onFinished` fires when it
/// ends (the win card waits for it) or at once on a tap.
struct WinAnimationView: View {
    let kind: WinAnimation
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        switch kind {
        case .rainfall: WinRainfall(foundations: foundations, layout: layout, onFinished: onFinished)
        case .decay: WinDecay(foundations: foundations, layout: layout, onFinished: onFinished)
        case .shuffle: WinShuffle(foundations: foundations, layout: layout, onFinished: onFinished)
        default: WinCascade(foundations: foundations, layout: layout, onFinished: onFinished)
        }
    }
}

// MARK: - Timing (pure, so tests can check it)

/// Rainfall: kings first, round the four foundations, one card every 0.12 s drops from its pile
/// with a slight sway and a little spin, straight off the bottom.
enum RainfallTimeline {
    static let interval: TimeInterval = 0.12
    static let gravity: CGFloat = 1800

    /// Where launch number `index` is at `t` (seconds since the start): nil before it launches
    /// (it is still on its pile) and once it is below `bottom`.
    static func offset(index: Int, at t: TimeInterval, bottom: CGFloat) -> (dx: CGFloat, dy: CGFloat, angle: Double)? {
        let s = t - Double(index) * interval
        guard s >= 0 else { return nil }
        let dy = 0.5 * gravity * CGFloat(s * s)
        guard dy <= bottom else { return nil }
        let phase = Double(index) * 1.7
        return (14 * CGFloat(sin(s * 4 + phase)), dy, 10 * sin(s * 2.5 + phase))
    }

    static func launched(at t: TimeInterval, total: Int) -> Int {
        t < 0 ? 0 : min(total, Int(t / interval) + 1)
    }

    /// When the last card has fallen past `bottom`.
    static func duration(total: Int, bottom: CGFloat) -> TimeInterval {
        Double(max(total - 1, 0)) * interval + (2 * Double(bottom) / Double(gravity)).squareRoot()
    }
}

/// Decay: each pile dissolves from the top down — every card over 0.55 s, the next starting when
/// the one above is 60 % gone — the piles a quarter of a second apart.
enum DecayTimeline {
    static let cardDuration: TimeInterval = 0.55
    static let step: TimeInterval = 0.33
    static let pileStagger: TimeInterval = 0.25

    /// How far gone (0…1) the card `depth` from the top of pile `pile` is at `t`.
    static func progress(pile: Int, depth: Int, at t: TimeInterval) -> Double {
        let start = Double(pile) * pileStagger + Double(depth) * step
        return min(max((t - start) / cardDuration, 0), 1)
    }

    /// When the last card of the last pile is wholly gone (with a frame to spare, so rounding
    /// never ends it at 99.99 %).
    static func duration(deepest: Int) -> TimeInterval {
        3 * pileStagger + Double(max(deepest - 1, 0)) * step + cardDuration + 1.0 / 60
    }
}

/// Shuffle: the cards gather into two half-piles in the middle (0.9 s), riffle together into one
/// deck (1.2 s), turn face down (0.3 s) and slide onto the draw pile (0.6 s), where they stay.
enum ShuffleTimeline {
    static let gather: TimeInterval = 0.9
    static let riffle: TimeInterval = 1.2
    static let flip: TimeInterval = 0.3
    static let slide: TimeInterval = 0.6
    static var duration: TimeInterval { gather + riffle + flip + slide }

    static func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    /// Card number `i` of `total` (deck order after the riffle): its centre, and whether its face
    /// shows (the flip's first half) — given where it starts, the middle of the board, the draw
    /// pile and the card width.
    static func place(_ i: Int, of total: Int, at t: TimeInterval, from start: CGPoint,
                      middle: CGPoint, stock: CGPoint, cardWidth: CGFloat) -> (center: CGPoint, faceUp: Bool, squeeze: CGFloat) {
        let left = i % 2 == 0
        let half = CGPoint(x: middle.x + (left ? -0.85 : 0.85) * cardWidth, y: middle.y - CGFloat(i / 2) * 0.4)
        let stacked = CGPoint(x: middle.x, y: middle.y - CGFloat(i) * 0.4)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        if t < gather {
            let k = ease((t - Double(i) * 0.008) / (gather - 0.4))
            return (lerp(start, half, k), true, 1)
        }
        let r = t - gather
        if r < riffle {
            let hop = Double(i) / Double(max(total, 1)) * (riffle - 0.15)
            return (lerp(half, stacked, ease((r - hop) / 0.15)), true, 1)
        }
        let f = r - riffle
        if f < flip {
            let k = f / flip
            return (stacked, k < 0.5, CGFloat(abs(1 - 2 * k)))     // narrows to an edge, then the back widens
        }
        let k = ease((f - flip) / slide)
        let deck = CGPoint(x: stock.x, y: stock.y - CGFloat(i) * 0.25)
        return (lerp(stacked, deck, k), false, 1)
    }
}

// MARK: - The views

/// The shared frame for Rainfall, Decay and Shuffle: a timeline from the first frame, the card
/// images as Canvas symbols (`back` for face-down), finishing once, and a tap to skip.
private struct WinTimelineCanvas: View {
    let cards: [Card]
    let cardWidth: CGFloat
    let duration: TimeInterval
    let onFinished: () -> Void
    let draw: (inout GraphicsContext, CGSize, TimeInterval) -> Void
    @State private var clock = AnimationClock()
    @State private var finished = false

    static let backID = -1

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            Canvas { context, size in
                let t = clock.elapsed(at: timeline.date)
                draw(&context, size, t)
                if t >= duration && !finished {
                    Task { @MainActor in
                        finished = true
                        onFinished()
                    }
                }
            } symbols: {
                ForEach(cards) { card in
                    CardView(card: card, width: cardWidth).tag(card.id)
                }
                CardView(card: Card(suit: .spades, rank: 1, isFaceUp: false), width: cardWidth).tag(Self.backID)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        .accessibilityHidden(true)
    }
}

/// The animation's own clock: started by the first frame it draws, like the cascade's simulation
/// (a reference type, so drawing can start it without a view update).
final class AnimationClock {
    private var start: Date?

    func elapsed(at date: Date) -> TimeInterval {
        if start == nil { start = date }
        return date.timeIntervalSince(start ?? date)
    }
}

private struct WinRainfall: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        let order = CascadeSimulation.launchOrder(foundations)
        let bottom = layout.metrics.size.height + layout.metrics.cardHeight
        WinTimelineCanvas(cards: order, cardWidth: layout.metrics.cardWidth,
                          duration: RainfallTimeline.duration(total: order.count, bottom: bottom),
                          onFinished: onFinished) { context, _, t in
            let launched = RainfallTimeline.launched(at: t, total: order.count)
            for (f, card) in CascadeSimulation.remainingTops(foundations, launched: launched).enumerated() {
                guard let card, let symbol = context.resolveSymbol(id: card.id) else { continue }
                let slot = layout.slot(.foundation(f))
                context.draw(symbol, at: CGPoint(x: slot.midX, y: slot.midY))
            }
            for (i, card) in order.enumerated() {
                guard let o = RainfallTimeline.offset(index: i, at: t, bottom: bottom),
                      let symbol = context.resolveSymbol(id: card.id),
                      let f = foundations.firstIndex(where: { $0.contains(card) }) else { continue }
                let slot = layout.slot(.foundation(f))
                var c = context
                c.translateBy(x: slot.midX + o.dx, y: slot.midY + o.dy)
                c.rotate(by: .degrees(o.angle))
                c.draw(symbol, at: .zero)
            }
        }
    }
}

private struct WinDecay: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        let deepest = foundations.map(\.count).max() ?? 0
        let width = layout.metrics.cardWidth
        WinTimelineCanvas(cards: foundations.flatMap { $0 }, cardWidth: width,
                          duration: DecayTimeline.duration(deepest: deepest), onFinished: onFinished) { context, _, t in
            for (f, pile) in foundations.enumerated() {
                let slot = layout.slot(.foundation(f))
                let center = CGPoint(x: slot.midX, y: slot.midY)
                // The card being eaten away and the one under it (which shows through the holes).
                let depths = (0..<pile.count).filter { DecayTimeline.progress(pile: f, depth: $0, at: t) < 1 }.prefix(2)
                for depth in depths.reversed() {
                    let card = pile[pile.count - 1 - depth]
                    guard let symbol = context.resolveSymbol(id: card.id) else { continue }
                    let p = DecayTimeline.progress(pile: f, depth: depth, at: t)
                    if p <= 0 {
                        context.draw(symbol, at: center)
                    } else {
                        context.drawLayer { layer in
                            layer.addFilter(.layerShader(Dissolve.shader(progress: p, seed: card.id, cardWidth: width),
                                                         maxSampleOffset: .zero))
                            layer.draw(symbol, at: center)
                        }
                    }
                }
            }
        }
    }
}

/// The dissolve shader (Dissolve.metal), as Decay and the tests use it.
enum Dissolve {
    static func shader(progress: Double, seed: Int, cardWidth: CGFloat) -> Shader {
        ShaderLibrary.dissolve(.float(Float(progress)), .float(Float(seed)), .float(Float(cardWidth / 7)))
    }
}

private struct WinShuffle: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        // Deck order after the riffle: the two halves interleaved.
        let deck = CascadeSimulation.launchOrder(foundations)
        let stockSlot = layout.slot(.stock)
        let width = layout.metrics.cardWidth
        WinTimelineCanvas(cards: deck, cardWidth: width, duration: ShuffleTimeline.duration,
                          onFinished: onFinished) { context, size, t in
            let middle = CGPoint(x: size.width / 2, y: size.height * 0.45)
            for (i, card) in deck.enumerated() {
                let f = foundations.firstIndex { $0.contains(card) } ?? 0
                let slot = layout.slot(.foundation(f))
                let place = ShuffleTimeline.place(i, of: deck.count, at: t, from: CGPoint(x: slot.midX, y: slot.midY),
                                                  middle: middle, stock: CGPoint(x: stockSlot.midX, y: stockSlot.midY),
                                                  cardWidth: width)
                guard let symbol = context.resolveSymbol(id: place.faceUp ? card.id : WinTimelineCanvas.backID) else { continue }
                var c = context
                c.translateBy(x: place.center.x, y: place.center.y)
                c.scaleBy(x: max(place.squeeze, 0.02), y: 1)
                c.draw(symbol, at: .zero)
            }
        }
    }
}
