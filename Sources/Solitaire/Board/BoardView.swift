import SwiftUI
import SolitaireEngine

/// The table: pile outlines plus all 52 cards, each placed by `BoardLayout`. A card moving
/// between piles is the same view animating to a new frame (0.2 s ease-out) — for every state
/// change: a tap, a draw, auto-finish steps, undo, a new deal. A flip rotates over 0.25 s.
/// Reduce Motion turns every animation off, including the wiggle and the win cascade.
///
/// Input (spec "Interaction"): a tap or click sends a card to its auto destination, or wiggles it
/// for 0.25 s if there is none; a drag lifts the card and its run after 8 pt, tracks 1:1 above
/// every pile, drops on the nearest pile, and springs home in 0.2 s if the drop is illegal; a
/// macOS double-click acts once, like a tap; hovering highlights the card under the pointer.
struct BoardView: View {
    let store: GameStore
    /// Called when the win cascade has finished (or was clicked to skip it).
    var onCascadeFinished: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.winAnimation) private var winAnimation
    @Environment(\.displayScale) private var displayScale
    @Environment(\.cardStyle) private var cardStyle
    @Environment(\.drawPileSide) private var drawPileSide
    @State private var dragTranslation: CGSize = .zero
    /// True while a drag gesture is live; resets on its own when the system cancels the gesture
    /// (which skips `onEnded`), so a cancelled drag still ends and springs home.
    @GestureState private var isDragging = false
    @State private var hoveredID: Int?
    @State private var wiggles: [Int: Int] = [:]      // card id → wiggle count (the animation trigger)
    @State private var router = TapRouter(clicks: ClickFilter(interval: BoardView.doubleClickInterval),
                                          filtersRepeatClicks: !BoardView.isTouch)

    static let moveAnimation = Animation.easeOut(duration: 0.2)
    static let flipAnimation = Animation.easeOut(duration: 0.25)
    static let springBack = Animation.easeOut(duration: 0.2)
    static let dragThreshold: CGFloat = 8
    static let space = "board"

    var body: some View {
        GeometryReader { geo in
            let metrics = BoardMetrics(size: geo.size, isTouch: Self.isTouch)
            let layout = BoardLayout(state: store.state, metrics: metrics, raised: store.movedCardIDs,
                                     side: drawPileSide)
            ZStack(alignment: .topLeading) {
                outlines(layout)
                ForEach(layout.placements) { p in
                    card(p, layout)
                        // During the cascade the cascade draws the foundations, emptying them as
                        // the cards fly; the board's own copies stay for VoiceOver, unseen.
                        .opacity(cascading && p.isOnFoundation ? 0 : 1)
                }
                if cascading {
                    WinAnimationView(kind: winAnimation ?? .cascade, foundations: store.state.foundations,
                                     layout: layout, onFinished: onCascadeFinished)
                        .id(store.state.seed)               // a fresh cascade for every win
                        .zIndex(4000)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Draw the cascade's card images ahead of the win, a few per frame, once it is in reach.
            .task(id: CascadePrep(near: store.canAutoFinish || store.state.isWon,
                                  width: metrics.cardWidth, scale: displayScale, style: cardStyle)) {
                guard !reduceMotion, store.canAutoFinish || store.state.isWon else { return }
                let s = store.state
                await CardImageCache.shared.prepare(s.stock + s.waste + s.foundations.flatMap { $0 }
                                                    + s.tableau.flatMap { $0 },
                                                    width: metrics.cardWidth, scale: displayScale, style: cardStyle)
            }
            .coordinateSpace(.named(Self.space))
            .animation(reduceMotion ? nil : Self.moveAnimation, value: store.state)
            .animation(reduceMotion ? nil : Self.moveAnimation, value: drawPileSide)   // the top row slides across
            // However a drag ends — dropped, refused, cancelled by the system, or cut short by a
            // state change such as undo — the lifted cards settle: home in 0.2 s, or with the move.
            .onChange(of: store.pendingDrag) { _, drag in
                if drag == nil, dragTranslation != .zero {
                    withAnimation(reduceMotion ? nil : Self.springBack) { dragTranslation = .zero }
                }
            }
            .onChange(of: isDragging) { _, dragging in
                if !dragging, store.pendingDrag != nil { store.cancelDrag() }
            }
        }
    }

    private struct CascadePrep: Equatable {
        let near: Bool
        let width: CGFloat
        let scale: CGFloat
        let style: CardStyle
    }

    /// The win cascade runs (Reduce Motion: there is none).
    /// A won game plays its win animation (spec "Win animations") — none under Reduce Motion or
    /// when the player chose None.
    private var cascading: Bool { store.state.isWon && !reduceMotion && winAnimation != nil }

    private func card(_ p: CardPlacement, _ layout: BoardLayout) -> some View {
        let metrics = layout.metrics
        let role = CardAccessibility.of(p, in: store.state)
        let lifted = isLifted(p)
        return CardView(card: p.card, width: metrics.cardWidth,
                        isHighlighted: hoveredID == p.card.id && p.card.isFaceUp,
                        hasShadow: p.isExposed || lifted, isLifted: lifted)
            .animation(reduceMotion ? nil : Self.flipAnimation, value: p.card.isFaceUp)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: wiggles[p.card.id, default: 0]) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                // 0.25 s: left, right, left, right, home.
                LinearKeyframe(-6, duration: 0.05)
                LinearKeyframe(6, duration: 0.05)
                LinearKeyframe(-4, duration: 0.05)
                LinearKeyframe(4, duration: 0.05)
                LinearKeyframe(0, duration: 0.05)
            }
            .contentShape(Rectangle().inset(by: -(metrics.hitWidth - metrics.cardWidth) / 2))
            .onTapGesture(coordinateSpace: .named(Self.space)) { point in tapped(p, layout, at: point) }
            .gesture(drag(p, layout))
            .onHover { inside in
                if inside { hoveredID = p.card.id } else if hoveredID == p.card.id { hoveredID = nil }
            }
            .accessibilityElement()
            .accessibilityLabel(role.text)
            .accessibilityAddTraits(role.isButton ? .isButton : [])
            .accessibilityAction { tapped(p, layout, at: nil) }
            .accessibilityHidden(role == .hidden)
            .position(x: p.frame.midX, y: p.frame.midY)
            .offset(lifted ? dragTranslation : .zero)
            .zIndex(lifted ? 3000 + p.zIndex : p.zIndex)
    }

    // MARK: Drag

    /// The dragged card and every card above it in its pile.
    private func isLifted(_ p: CardPlacement) -> Bool {
        guard let drag = store.pendingDrag else { return false }
        return p.pile == drag.source && p.index >= drag.index
    }

    private func drag(_ p: CardPlacement, _ layout: BoardLayout) -> some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if store.pendingDrag == nil {
                    guard store.beginDrag(pile: p.pile, index: p.index) else { return }
                }
                guard store.pendingDrag == p.asDrag else { return }
                dragTranslation = value.translation
            }
            .onEnded { value in
                guard let drag = store.pendingDrag else { return }
                guard drag == p.asDrag else {
                    // The card changed place mid-drag: end the drag rather than leave it pending.
                    store.cancelDrag()
                    return
                }
                let center = CGPoint(x: p.frame.midX + value.translation.width,
                                     y: p.frame.midY + value.translation.height)
                let target = layout.dropTarget(for: center)
                // Legal: the card animates from where it was dropped to its new pile.
                // Illegal: it springs home in 0.2 s.
                if let target, SolitaireEngine.canMove(Move(source: drag.source, index: drag.index,
                                                            destination: target), in: store.state) {
                    withAnimation(reduceMotion ? nil : Self.moveAnimation) {
                        store.drop(source: drag.source, index: drag.index, on: target)
                        dragTranslation = .zero
                    }
                } else {
                    withAnimation(reduceMotion ? nil : Self.springBack) {
                        store.cancelDrag()
                        dragTranslation = .zero
                    }
                }
            }
    }

    // MARK: Tap

    private func tapped(_ p: CardPlacement, _ layout: BoardLayout, at point: CGPoint?) {
        switch router.route(p.pile, at: point) {
        case .draw:
            store.tapStock()
            return
        case .ignore:
            return
        case .move:
            break
        }
        if store.tap(pile: p.pile, index: p.index) { return }
        // Nowhere to go: wiggle the card and its run (face-up waste and column cards only; a tap
        // on a foundation does nothing by design, and face-down cards are not playable).
        guard !reduceMotion, p.card.isFaceUp else { return }
        switch p.pile {
        case .waste, .tableau:
            for q in layout.placements where q.pile == p.pile && q.index >= p.index {
                wiggles[q.card.id, default: 0] += 1
            }
        default:
            break
        }
    }

    // MARK: Outlines

    private func outlines(_ layout: BoardLayout) -> some View {
        let w = layout.metrics.cardWidth
        let state = store.state
        let redeal = SolitaireEngine.canRedeal(state)
        let outOfPasses = SolitaireEngine.isOutOfPasses(state)        // Hard Core: ✕, nothing to do
        let stockLabel = !state.stock.isEmpty ? "Stock, \(state.stock.count) cards"
            : redeal ? "Stock, empty. Redeal" : outOfPasses ? "Stock, empty. No passes left" : "Stock, empty"
        return ZStack(alignment: .topLeading) {
            // VoiceOver: the stock is always this one element (its cards are hidden). Taps on the
            // stock's cards reach `tapStock` through the cards themselves; this handles the empty stock.
            outline(layout.slot(.stock), w, symbol: redeal ? "arrow.counterclockwise" : outOfPasses ? "xmark" : nil,
                    label: stockLabel, spoken: true, action: { store.tapStock() })
            outline(layout.slot(.waste), w, label: "Waste, empty", spoken: state.waste.isEmpty)
            ForEach(0..<4, id: \.self) { f in
                outline(layout.slot(.foundation(f)), w, symbol: "a.square", label: "Foundation \(f + 1), empty",
                        spoken: state.foundations[f].isEmpty)
            }
            ForEach(0..<7, id: \.self) { t in
                outline(layout.slot(.tableau(t)), w, label: "Column \(t + 1), empty",
                        spoken: state.tableau[t].isEmpty)
            }
        }
    }

    /// A pile's outline. Gestures and accessibility attach before `.position`, so both cover the
    /// outline only (a positioned view fills the whole board).
    @ViewBuilder
    private func outline(_ rect: CGRect, _ width: CGFloat, symbol: String? = nil, label: String,
                         spoken: Bool, action: (() -> Void)? = nil) -> some View {
        let base = PileOutline(width: width, symbol: symbol)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHidden(!spoken)
        if let action {
            base
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
                .position(x: rect.midX, y: rect.midY)
        } else {
            base.position(x: rect.midX, y: rect.midY)
        }
    }

    static var isTouch: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    static var doubleClickInterval: TimeInterval {
        #if os(macOS)
        NSEvent.doubleClickInterval
        #else
        0
        #endif
    }
}

extension CardPlacement {
    /// The pending drag picking up this card would start.
    var asDrag: GameStore.PendingDrag { GameStore.PendingDrag(source: pile, index: index) }
}

extension CardAccessibility {
    var text: String {
        switch self {
        case .hidden: ""
        case .label(let s), .button(let s): s
        }
    }

    var isButton: Bool {
        if case .button = self { true } else { false }
    }
}
