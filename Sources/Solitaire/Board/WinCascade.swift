import SwiftUI
import SolitaireEngine

/// The classic win cascade, in SwiftUI (no SpriteKit): kings first, the cards leap off the
/// foundations one after another — each pile showing the next card down, until all four are
/// empty — fall, bounce along the bottom of the board leaving a trail, and leave the screen. The
/// whole trail stays on the felt afterwards. `onFinished` fires once the last card has gone (the
/// win sheet waits for it), or at once if the cascade is clicked. Not shown under Reduce Motion
/// (the board decides).
struct WinCascade: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.cardStyle) private var cardStyle
    @State private var simulation = CascadeSimulation()
    @State private var trail = TrailBitmap()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            Canvas { context, size in
                simulation.advance(to: timeline.date, launches: launches, bounds: size,
                                   cardHeight: layout.metrics.cardHeight)
                // The piles: what has not launched yet, under the flying cards.
                let tops = CascadeSimulation.remainingTops(foundations, launched: simulation.launched)
                for (f, card) in tops.enumerated() {
                    guard let card, let symbol = context.resolveSymbol(id: card.id) else { continue }
                    let slot = layout.slot(.foundation(f))
                    context.draw(symbol, at: CGPoint(x: slot.midX, y: slot.midY))
                }
                // The trail: older stamps baked into one bitmap, the newest drawn card by card.
                trail.bake(simulation.stamps, size: size, displayScale: displayScale,
                           final: simulation.isFinished)
                if let image = trail.image {               // at its own size: never stretched
                    context.draw(Image(decorative: image, scale: trail.scale),
                                 in: CGRect(origin: .zero, size: trail.size))
                }
                for stamp in simulation.stamps[trail.baked...] {
                    guard let symbol = context.resolveSymbol(id: stamp.cardID) else { continue }
                    context.draw(symbol, at: stamp.center)
                }
                if simulation.isFinished && !finished {
                    Task { @MainActor in                         // not during the render pass
                        finished = true
                        onFinished()
                    }
                }
            } symbols: {
                ForEach(foundations.flatMap { $0 }) { card in
                    CardView(card: card, width: layout.metrics.cardWidth).tag(card.id)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }                          // skip ahead to the win sheet
        .task {
            // Usually ready already (the board prepares them once the game can auto-finish).
            let cards = foundations.flatMap { $0 }
            let width = layout.metrics.cardWidth
            await CardImageCache.shared.prepare(cards, width: width, scale: displayScale, style: cardStyle)
            if let images = CardImageCache.shared.images(for: cards, width: width, scale: displayScale, style: cardStyle) {
                trail.cardScale = displayScale
                trail.cards = images
            }
        }
        .accessibilityHidden(true)
    }

    /// Kings first, across the four foundations, then queens, and so on down to the aces.
    private var launches: [(cardID: Int, from: CGPoint)] {
        CascadeSimulation.launchOrder(foundations).map { card in
            let f = foundations.firstIndex { $0.contains(card) } ?? 0
            let slot = layout.slot(.foundation(f))
            return (card.id, CGPoint(x: slot.midX, y: slot.midY))
        }
    }
}

/// Plain physics in fixed time steps, so the motion and the trail spacing are the same at 60 and
/// 120 Hz. A reference type so the Canvas can advance it while drawing without triggering view
/// updates. Every stamp is kept: the trail is the picture the cascade leaves behind.
final class CascadeSimulation {
    struct Stamp { let cardID: Int; let center: CGPoint }
    private struct Flyer { let cardID: Int; var position: CGPoint; var velocity: CGVector }

    static let launchInterval: TimeInterval = 0.18
    static let step: TimeInterval = 1.0 / 120
    static let stampEvery = 2                       // steps: one trail stamp per 1/60 s
    static let gravity: CGFloat = 1600
    static let restitution: CGFloat = 0.72

    private var start: Date?
    private var simulated: TimeInterval = 0
    private var steps = 0
    private var total = 0
    private var flyers: [Flyer] = []
    private var rng = SplitMix64(seed: 2026)
    /// How many cards have left the foundations so far.
    private(set) var launched = 0
    private(set) var stamps: [Stamp] = []

    /// Every card has launched and left the board.
    var isFinished: Bool { total > 0 && launched == total && flyers.isEmpty }

    /// Kings first, across the four foundations, then queens, and so on down to the aces.
    static func launchOrder(_ foundations: [[Card]]) -> [Card] {
        (0..<13).reversed().flatMap { rank in
            foundations.compactMap { $0.indices.contains(rank) ? $0[rank] : nil }
        }
    }

    /// The card left showing on each foundation once `launched` cards have flown (nil: empty).
    static func remainingTops(_ foundations: [[Card]], launched: Int) -> [Card?] {
        let gone = Set(launchOrder(foundations).prefix(launched).map(\.id))
        return foundations.map { pile in pile.last { !gone.contains($0.id) } }
    }

    func advance(to now: Date, launches: [(cardID: Int, from: CGPoint)], bounds: CGSize, cardHeight: CGFloat) {
        let start = self.start ?? now
        self.start = start
        total = launches.count
        // Catch up in fixed steps, but never more than a quarter second at once (after a stall).
        let target = min(now.timeIntervalSince(start), simulated + 0.25)
        let floor = bounds.height - cardHeight / 2        // the card's edge, not its centre, meets the bottom
        while simulated + Self.step <= target {
            simulated += Self.step
            steps += 1
            launch(upTo: simulated, launches)
            for i in flyers.indices {
                flyers[i].velocity.dy += Self.gravity * Self.step
                flyers[i].position.x += flyers[i].velocity.dx * Self.step
                flyers[i].position.y += flyers[i].velocity.dy * Self.step
                if flyers[i].position.y > floor, flyers[i].velocity.dy > 0 {
                    flyers[i].position.y = floor
                    flyers[i].velocity.dy *= -Self.restitution
                }
                if steps % Self.stampEvery == 0 {
                    stamps.append(Stamp(cardID: flyers[i].cardID, center: flyers[i].position))
                }
            }
            flyers.removeAll { $0.position.x < -200 || $0.position.x > bounds.width + 200 }
        }
    }

    private func launch(upTo time: TimeInterval, _ launches: [(cardID: Int, from: CGPoint)]) {
        while launched < launches.count, time >= Double(launched) * Self.launchInterval {
            let l = launches[launched]
            let speed = CGFloat(120 + rng.next() % 220)
            let direction: CGFloat = rng.next() % 2 == 0 ? -1 : 1
            flyers.append(Flyer(cardID: l.cardID, position: l.from,
                                velocity: CGVector(dx: direction * speed, dy: -CGFloat(rng.next() % 240))))
            launched += 1
        }
    }
}

/// The trail, accumulated: stamps are drawn once into a bitmap, in batches, so a frame costs one
/// image plus the latest few hundred cards however long the trail grows. (Redrawing every stamp
/// each frame is what forced the old cap — and the cap erased the start of the trail.)
final class TrailBitmap {
    static let batch = 240                         // stamps per bake: about a quarter second's worth
    /// The bitmap's pixel budget (about 24 MB). A huge window draws its baked trail at a little
    /// less than full resolution rather than holding 40+ MB; the newest stamps stay crisp.
    static let maxPixels: CGFloat = 6_000_000
    /// Every card image, all at once (a missing one would drop its stamps from the trail for good).
    var cards: [Int: CGImage] = [:]
    /// The scale the card images were drawn at.
    var cardScale: CGFloat = 1
    private(set) var image: CGImage?
    private(set) var baked = 0
    /// The board size (points) and pixel scale the bitmap was made for.
    private(set) var size: CGSize = .zero
    private(set) var scale: CGFloat = 1
    private var context: CGContext?

    static func bitmapScale(for size: CGSize, displayScale: CGFloat) -> CGFloat {
        min(displayScale, (maxPixels / max(size.width * size.height, 1)).squareRoot())
    }

    /// Bakes the pending stamps once a batch has built up, or all of them when the cascade ends.
    /// If the board's size or scale changed (a window resized, or moved to another display), the
    /// bitmap is rebuilt from every stamp at the new size rather than stretched.
    func bake(_ stamps: [CascadeSimulation.Stamp], size: CGSize, displayScale: CGFloat, final: Bool) {
        let scale = Self.bitmapScale(for: size, displayScale: displayScale)
        if context != nil, size != self.size || scale != self.scale {
            context = nil
            image = nil
            baked = 0
        }
        let pending = stamps.count - baked
        guard pending > 0, pending >= Self.batch || final, !cards.isEmpty else { return }
        if context == nil {
            let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
            guard w > 0, h > 0, let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // Top-left origin, in points — the same space as the stamps.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: scale, y: -scale)
            context = ctx
            self.size = size
            self.scale = scale
        }
        guard let context else { return }
        for stamp in stamps[baked...] {
            guard let card = cards[stamp.cardID] else { continue }
            let w = CGFloat(card.width) / cardScale, h = CGFloat(card.height) / cardScale
            let rect = CGRect(x: stamp.center.x - w / 2, y: stamp.center.y - h / 2, width: w, height: h)
            // CGContext.draw puts an image's top at the rect's maxY; flip it back locally.
            context.saveGState()
            context.translateBy(x: 0, y: rect.midY * 2)
            context.scaleBy(x: 1, y: -1)
            context.draw(card, in: rect)
            context.restoreGState()
        }
        baked = stamps.count
        image = context.makeImage()
    }
}

/// The cascade's card images, drawn a few per frame and ahead of the win: rendering all 52 at the
/// instant of winning would stall the cascade's first frames. Keeps one set — the current card
/// width, scale and card style.
@MainActor final class CardImageCache {
    static let shared = CardImageCache()
    private var images: [Int: CGImage] = [:]
    private var width: CGFloat = 0
    private var scale: CGFloat = 0
    private var style = CardStyle()

    func prepare(_ cards: [Card], width: CGFloat, scale: CGFloat, style: CardStyle) async {
        if width != self.width || scale != self.scale || style != self.style {
            images = [:]
            self.width = width
            self.scale = scale
            self.style = style
        }
        for card in cards where images[card.id] == nil {
            let renderer = ImageRenderer(content: CardView(card: card, width: width).environment(\.cardStyle, style))
            renderer.scale = scale
            images[card.id] = renderer.cgImage
            try? await Task.sleep(for: .milliseconds(2))     // let a frame through between cards
            guard width == self.width, scale == self.scale, style == self.style else { return }   // superseded
        }
    }

    /// All the cards' images at this width, scale and style, or nil until every one is ready.
    func images(for cards: [Card], width: CGFloat, scale: CGFloat, style: CardStyle) -> [Int: CGImage]? {
        guard width == self.width, scale == self.scale, style == self.style else { return nil }
        var out: [Int: CGImage] = [:]
        for card in cards {
            guard let image = images[card.id] else { return nil }
            out[card.id] = image
        }
        return out
    }
}
