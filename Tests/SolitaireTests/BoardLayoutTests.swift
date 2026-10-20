import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SolitaireEngine
@testable import Solitaire

/// The board area (inside safe areas and the toolbar) for the spec's layout acceptance sizes.
/// Derived from each device's points: screen − status bar/home indicator/side insets − toolbar.
enum BoardSize: String, CaseIterable {
    case iPhoneSEPortrait        // 375 × 667; status 20
    case iPhoneSELandscape       // 667 × 375
    case iPhoneProMaxLandscape   // 956 × 440; side insets 2 × 62, home 21
    case iPadThirdSplit          // 320-pt split column on an 11" iPad; status 24
    case mac600                  // the smallest Mac window (SolitaireApp.minimumWindow)

    /// The board's space on each: the screen less direction A's header (48 pt) and bottom bar
    /// (60 pt buttons + 16), and any safe-area insets — on a phone held sideways, only the shorter
    /// bar the header folds into (52 + 16). The board runs edge to edge.
    var size: CGSize {
        let chrome: CGFloat = 48 + 76
        let landscapeChrome: CGFloat = 52 + 16
        return switch self {
        case .iPhoneSEPortrait: CGSize(width: 375, height: 667 - 20 - chrome)
        case .iPhoneSELandscape: CGSize(width: 667, height: 375 - landscapeChrome)
        case .iPhoneProMaxLandscape: CGSize(width: 956 - 124, height: 440 - 21 - landscapeChrome)
        case .iPadThirdSplit: CGSize(width: 320, height: 1180 - 24 - chrome)
        case .mac600: CGSize(width: SolitaireApp.minimumWindow.width, height: SolitaireApp.minimumWindow.height - chrome)
        }
    }

    var isTouch: Bool { self != .mac600 }
}

/// A position with the tallest column the rules allow: 6 face-down cards under a full K→A run.
func worstCaseState() -> GameState {
    let down = (2...7).map { Card(suit: .clubs, rank: $0, isFaceUp: false) }
    let run = (1...13).reversed().map { rank in
        Card(suit: rank % 2 == 1 ? .spades : .hearts, rank: rank, isFaceUp: true)
    }
    var s = SolitaireEngine.newGame(drawCount: 3, seed: 1)
    s.tableau = [[], [], [], [], [], [], down + run]
    s.stock = []
    s.waste = []
    return s
}

@Suite struct Metrics {
    @Test func followsTheSpecRatios() {
        let m = BoardMetrics(size: CGSize(width: 700, height: 2000), isTouch: false)
        #expect(abs(m.gap - 700 * 0.018) < 0.001)
        #expect(abs(m.cardWidth - (700 - 8 * m.gap) / 7) < 0.001)
        #expect(abs(m.cardHeight - m.cardWidth * 1.4) < 0.001)
        #expect(abs(m.cornerRadius - m.cardWidth * 0.09) < 0.001)
        #expect(abs(m.faceDownFan - m.cardHeight * 0.12) < 0.001)
        #expect(abs(m.faceUpFan - m.cardHeight * 0.29) < 0.001)
        #expect(!m.isCompressed)
    }

    @Test func boardWidthIsCappedAt900AndCentred() {
        let m = BoardMetrics(size: CGSize(width: 2000, height: 4000), isTouch: false)
        #expect(abs(m.cardWidth - (900 - 8 * 900 * 0.018) / 7) < 0.001)
        #expect(abs(m.leftEdge - (2000 - m.usedWidth) / 2) < 0.001)
    }

    /// Boards 500 pt and wider: gaps are 1.8 % of the width but never under 4 pt, margins equal to them.
    @Test func wideBoardGapsNeverBelowFourPoints() {
        let m = BoardMetrics(size: CGSize(width: 520, height: 2000), isTouch: false)
        #expect(m.gap == 520 * 0.018 || m.gap == 4)
        #expect(m.gap >= 4 && m.margin == m.gap)
    }

    /// Direction A: phone-width boards use 3 pt gaps inside 4 pt margins, for bigger cards.
    @Test func narrowBoardsUseTightGutters() {
        let m = BoardMetrics(size: CGSize(width: 390, height: 640), isTouch: true)
        #expect(m.gap == 3 && m.margin == 4)
        #expect(abs(m.cardWidth - (390 - 2 * 4 - 6 * 3) / 7) < 0.001)
        #expect(abs(m.leftEdge - 4) < 0.001, "the outer columns sit 4 pt from the edges")
    }

    /// The space under the top row is 0.8 × card width (portrait phones and the Mac alike).
    @Test(arguments: [(CGSize(width: 390, height: 640), true), (CGSize(width: 1000, height: 640), false)])
    func rowGapIsEightyPercentOfACardWidth(_ size: CGSize, _ touch: Bool) {
        let m = BoardMetrics(size: size, isTouch: touch)
        #expect(m.rowGapCap == nil)
        #expect(abs(m.tableauY - (m.topRowY + m.cardHeight) - 0.8 * m.cardWidth) < 0.001)
    }

    /// The smallest Mac window keeps cards about 50 pt wide (review R3; at 420 pt tall they were ~37).
    @Test func theSmallestMacWindowKeepsCardsLarge() {
        #expect(BoardMetrics(size: BoardSize.mac600.size, isTouch: false).cardWidth >= 50)
    }

    /// The chip shows this game's mode and offers the other (spec "New games and the draw mode").
    @Test func drawChipShowsThisGamesModeAndOffersTheOther() {
        #expect(GameHeader.drawChip(current: 1) == ("DRAW 1", "Draw one", "Switches to Draw 3 and starts a new game", 3))
        #expect(GameHeader.drawChip(current: 3) == ("DRAW 3", "Draw three", "Switches to Draw 1 and starts a new game", 1))
        #expect(GameHeader.drawChip(current: 1, hardCore: true).text == "DRAW 1 · HC")
        #expect(GameHeader.drawChip(current: 1, hardCore: true).spoken == "Draw one, Hard Core")
    }

    /// A touch board held sideways caps that space at 16 pt — height is what limits its cards.
    @Test func landscapeTouchBoardsCapTheRowGap() {
        let m = BoardMetrics(size: BoardSize.iPhoneProMaxLandscape.size, isTouch: true)
        #expect(m.rowGapCap == 16)
        #expect(abs(m.rowGap - min(0.8 * m.cardWidth, 16)) < 0.001)
        #expect(m.tableauY - (m.topRowY + m.cardHeight) <= 16 + 0.001)
        let mouse = BoardMetrics(size: BoardSize.iPhoneProMaxLandscape.size, isTouch: false)
        #expect(mouse.rowGapCap == nil, "a Mac window is not a device held sideways")
    }

    /// Decision D1: on short, wide boards cards are capped so a column of six face-down cards under
    /// a K→5 run keeps readable fans; a fresh deal is never squeezed.
    @Test(arguments: [BoardSize.iPhoneProMaxLandscape, .mac600])
    func shortWideBoardsCapTheCardSizeByHeight(_ board: BoardSize) {
        let size = board.size
        let m = BoardMetrics(size: size, isTouch: board.isTouch)
        let byWidth = (min(size.width, 900) - 2 * m.margin - 6 * m.gap) / 7
        #expect(m.cardWidth < byWidth, "the height cap should bind here")
        // A real column: six face-down cards under K→5 (nine face-up cards, eight fan steps).
        var s = SolitaireEngine.newGame(drawCount: 1, seed: 1)
        let down = (2...7).map { Card(suit: .clubs, rank: $0, isFaceUp: false) }
        let run = (5...13).reversed().map { Card(suit: $0 % 2 == 1 ? .spades : .hearts, rank: $0, isFaceUp: true) }
        s.tableau = [[], [], [], [], [], [], down + run]
        let column = BoardLayout(state: s, metrics: m).placements.filter { $0.pile == .tableau(6) }
        let upSteps = zip(column.dropFirst(6), column.dropFirst(7)).map { $1.frame.minY - $0.frame.minY }
        #expect(upSteps.count == 8)
        #expect(upSteps.allSatisfy { $0 >= m.cardHeight * BoardMetrics.readableFanRatio - 0.01 },
                "K→5 stays readable: \(upSteps.first ?? 0) vs \(m.cardHeight * BoardMetrics.readableFanRatio)")
        // …and the cap is no tighter than that: a K→4 run is already squeezed below readable.
        let longer = (4...13).reversed().map { Card(suit: $0 % 2 == 1 ? .spades : .hearts, rank: $0, isFaceUp: true) }
        s.tableau[6] = down + longer
        let tight = BoardLayout(state: s, metrics: m).placements.filter { $0.pile == .tableau(6) }
        #expect(tight[8].frame.minY - tight[7].frame.minY < m.cardHeight * BoardMetrics.readableFanRatio)
        #expect(m.fans(faceDown: 6, faceUp: 0) == (m.faceDownFan, m.faceUpFan), "a fresh deal is not squeezed")
    }

    /// Where height is plentiful (portrait phones, iPads) the cap never binds: the spec's width rule wins.
    @Test(arguments: [BoardSize.iPhoneSEPortrait, .iPadThirdSplit])
    func tallBoardsKeepTheWidthRule(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: board.isTouch)
        #expect(abs(m.cardWidth - (min(board.size.width, 900) - 2 * m.margin - 6 * m.gap) / 7) < 0.001)
    }

    /// Decision D2: touch cards narrower than 44 pt widen their hit area to the whole column slot
    /// (on a phone-width board the gaps are already at their tightest, 3 pt).
    @Test func narrowTouchBoardsAreCompressedWithFullHitTargets() {
        let touch = BoardMetrics(size: BoardSize.iPadThirdSplit.size, isTouch: true)
        #expect(touch.isCompressed && touch.gap == 3)
        #expect(touch.hitWidth >= 44)
        let mouse = BoardMetrics(size: BoardSize.iPadThirdSplit.size, isTouch: false)
        #expect(!mouse.isCompressed)
    }

    /// Every touch board gives each card a tap target of at least 44 pt.
    @Test(arguments: BoardSize.allCases.filter(\.isTouch))
    func touchHitTargetsAreAtLeast44(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: true)
        #expect(m.hitWidth >= 44, "\(board): \(m.hitWidth)")
    }

    @Test func fansShrinkOnlyWhenAColumnWouldOverflow() {
        let m = BoardMetrics(size: CGSize(width: 700, height: 700), isTouch: false)
        #expect(m.fans(faceDown: 1, faceUp: 1) == (m.faceDownFan, m.faceUpFan))
        let squeezed = m.fans(faceDown: 6, faceUp: 12)
        #expect(squeezed.up < m.faceUpFan && squeezed.down < m.faceDownFan)
        #expect(abs(squeezed.up / squeezed.down - 0.29 / 0.12) < 0.001, "scaled together")
    }
}

/// Acceptance: the board lays out without clipping on iPhone SE portrait, iPhone Pro Max
/// landscape, iPad split view at one third, and a 600 pt wide Mac window.
@Suite struct NoClipping {
    @Test(arguments: BoardSize.allCases, DrawPileSide.allCases)
    func everyCardFitsTheBoard(_ board: BoardSize, _ side: DrawPileSide) {
        let m = BoardMetrics(size: board.size, isTouch: board.isTouch)
        for (name, state) in [("deal", SolitaireEngine.newGame(drawCount: 3, seed: 4)), ("worst", worstCaseState())] {
            var s = state
            if name == "deal" { SolitaireEngine.drawFromStock(&s) }   // three cards on the waste, fanned
            let layout = BoardLayout(state: s, metrics: m, side: side)
            let bounds = CGRect(origin: .zero, size: board.size).insetBy(dx: -0.001, dy: -0.001)
            for p in layout.placements {
                #expect(bounds.contains(p.frame), "\(board) \(name): \(p.card.id) at \(p.frame)")
            }
            // The top row and the tableau never overlap.
            let topRowBottom = m.topRowY + m.cardHeight
            #expect(layout.placements.filter { if case .tableau = $0.pile { true } else { false } }
                .allSatisfy { $0.frame.minY >= topRowBottom })
        }
        #expect(m.cardWidth >= 30, "\(board): cards too small to read (\(m.cardWidth) pt)")
    }
}

/// Renders the real board at each acceptance size to PNGs for a human to look at (they are
/// written under the test host's temporary directory, whose path is printed).
@MainActor @Suite struct Snapshots {
    @Test(arguments: BoardSize.allCases)
    func renderBoard(_ board: BoardSize) throws {
        for (name, state) in [("deal", SolitaireEngine.newGame(drawCount: 3, seed: 4)), ("worst", worstCaseState())] {
            var s = state
            if name == "deal" { SolitaireEngine.drawFromStock(&s) }
            let store = GameStore(drawCount: 3) { 4 }
            store.resume(from: s)
            let view = BoardView(store: store)
                .frame(width: board.size.width, height: board.size.height)
                .background(TableBackground())
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("board-snapshots")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(board.rawValue)-\(name).png")
            #if os(macOS)
            let image = try #require(renderer.nsImage)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            #else
            let data = try #require(renderer.uiImage?.pngData())
            #endif
            try data.write(to: url)
            print("SNAPSHOT \(url.path)")
        }
    }
}

@MainActor @Suite struct MovingCards {
    /// A card on its way to another pile is drawn above every other card, so it never slides under
    /// a deeper column during the animation.
    @Test func movedCardsAreRaisedAboveEverything() throws {
        let store = GameStore(drawCount: 1) { 4 }
        let move = try #require(legalMoves(store.state).first {
            SolitaireEngine.autoDestination(for: $0.source, index: $0.index, in: store.state) != nil })
        let card = store.state[move.source][move.index]
        #expect(store.tap(pile: move.source, index: move.index))
        #expect(store.movedCardIDs.contains(card.id))
        let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)
        let layout = BoardLayout(state: store.state, metrics: m, raised: store.movedCardIDs)
        let moved = try #require(layout.placements.first { $0.card.id == card.id })
        let others = layout.placements.filter { !store.movedCardIDs.contains($0.card.id) }
        #expect(others.allSatisfy { $0.zIndex < moved.zIndex })
    }

    /// Within every pile, later cards are always drawn above earlier ones — after a move, a draw, a
    /// new deal and a resume alike (a per-card raise once buried unmoved cards mid-pile).
    @Test func cardsStayInOrderWithinEveryPile() {
        let store = GameStore(drawCount: 3) { 4 }
        let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)
        func check(_ when: String) {
            let layout = BoardLayout(state: store.state, metrics: m, raised: store.movedCardIDs)
            let byPile = Dictionary(grouping: layout.placements, by: \.pile)
            for (pile, cards) in byPile {
                let z = cards.sorted { $0.index < $1.index }.map(\.zIndex)
                #expect(z == z.sorted() && Set(z).count == z.count, "\(when): \(pile) out of order")
            }
        }
        store.tapStock(); check("draw")
        if let m = legalMoves(store.state).first { store.drop(source: m.source, index: m.index, on: m.destination) }
        check("move")
        store.newGame(drawCount: 3); check("new deal")
        store.resume(from: worstCaseState()); check("resume")
    }

    @Test func theClockTickDoesNotLowerAMovingCard() {
        let store = GameStore(drawCount: 1) { 4 }
        store.tapStock()
        let moved = store.movedCardIDs
        #expect(!moved.isEmpty)
        store.tick()
        #expect(store.movedCardIDs == moved)
    }
}

@Suite struct VoiceOver {
    func roles(_ s: GameState) -> [Int: CardAccessibility] {
        let layout = BoardLayout(state: s, metrics: BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false))
        return Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.card.id, CardAccessibility.of($0, in: s)) })
    }

    @Test func buriedCardsAreHiddenAndTheStockIsNotReadCardByCard() {
        var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        SolitaireEngine.drawFromStock(&s)
        SolitaireEngine.drawFromStock(&s)
        let r = roles(s)
        #expect(s.stock.allSatisfy { r[$0.id] == .hidden })
        #expect(r[s.waste[0].id] == .hidden, "a buried waste card")
        #expect(r[s.waste[1].id] != .hidden, "the waste top")
        #expect(s.tableau.flatMap { $0 }.filter { !$0.isFaceUp }.allSatisfy { r[$0.id] == .hidden })
    }

    @Test func columnsSayWhatIsHiddenAndOnlyPlayableCardsAreButtons() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let r = roles(s)
        let top6 = s.tableau[6].last!
        #expect(r[top6.id]!.text.hasSuffix("column 7, 6 face-down cards under it"))
        #expect(r[s.tableau[0].last!.id]!.text.hasSuffix("column 1"))
        for t in 0..<7 {
            let card = s.tableau[t].last!
            let playable = SolitaireEngine.autoDestination(for: .tableau(t), index: s.tableau[t].count - 1, in: s) != nil
            #expect(r[card.id]!.isButton == playable)
        }
    }

    @Test func foundationTopIsNamedButNotAButton() {
        var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        s.foundations[0] = [Card(suit: .hearts, rank: 1, isFaceUp: true), Card(suit: .hearts, rank: 2, isFaceUp: true)]
        s.tableau = s.tableau.map { $0.filter { !($0.suit == .hearts && $0.rank <= 2) } }
        s.stock.removeAll { $0.suit == .hearts && $0.rank <= 2 }
        let r = roles(s)
        #expect(r[Card(suit: .hearts, rank: 2).id] == .label("2 of Hearts, foundation 1"))
        #expect(r[Card(suit: .hearts, rank: 1).id] == .hidden)
    }
}

@Suite struct Cascade {
    func launches() -> [(cardID: Int, from: CGPoint)] {
        (0..<52).map { ($0, CGPoint(x: 400, y: 60)) }
    }

    /// Same trail however often the screen refreshes.
    @Test func trailDoesNotDependOnFrameRate() {
        func run(fps: Double) -> Int {
            let sim = CascadeSimulation()
            let t0 = Date()
            for frame in 0...Int(0.5 * fps) {
                sim.advance(to: t0.addingTimeInterval(Double(frame) / fps), launches: launches(),
                            bounds: CGSize(width: 800, height: 600), cardHeight: 100)
            }
            return sim.stamps.count
        }
        let at60 = run(fps: 60), at120 = run(fps: 120)
        #expect(at60 > 0)
        #expect(at60 == at120)
    }

    @Test func cardsBounceOnTheBoardEdgeAndTheCascadeEnds() {
        let sim = CascadeSimulation()
        let t0 = Date()
        var frame = 0
        while !sim.isFinished && frame < 60 * 120 {
            sim.advance(to: t0.addingTimeInterval(Double(frame) / 60), launches: launches(),
                        bounds: CGSize(width: 800, height: 600), cardHeight: 100)
            #expect(sim.stamps.allSatisfy { $0.center.y <= 600 - 50 + 0.001 })
            frame += 1
        }
        #expect(sim.isFinished, "every card should leave the board")
    }

    /// The trail is the picture the cascade leaves behind: nothing is ever dropped from it, so the
    /// start of the trail is still there when the last card leaves.
    @Test func theTrailIsNeverTrimmed() {
        let sim = CascadeSimulation()
        let t0 = Date()
        var frame = 0, previous = 0
        var firstStamp: CascadeSimulation.Stamp?
        while !sim.isFinished && frame < 60 * 120 {
            sim.advance(to: t0.addingTimeInterval(Double(frame) / 60), launches: launches(),
                        bounds: CGSize(width: 2560, height: 1000), cardHeight: 100)
            #expect(sim.stamps.count >= previous)
            previous = sim.stamps.count
            if firstStamp == nil { firstStamp = sim.stamps.first }
            frame += 1
        }
        #expect(sim.isFinished)
        #expect(sim.stamps.count > 1400, "a wide board's trail is long (\(sim.stamps.count))")
        #expect(sim.stamps.first?.center == firstStamp?.center, "the first stamp is still there")
    }

    func fullFoundations() -> [[Card]] {
        [Suit.spades, .hearts, .diamonds, .clubs].map { s in (1...13).map { Card(suit: s, rank: $0, isFaceUp: true) } }
    }

    @Test func kingsLeaveFirstAndThePilesEmpty() {
        let f = fullFoundations()
        let order = CascadeSimulation.launchOrder(f)
        #expect(order.count == 52 && Set(order.map(\.id)).count == 52)
        #expect(order.prefix(4).allSatisfy { $0.rank == 13 } && order.last?.rank == 1)
        #expect(CascadeSimulation.remainingTops(f, launched: 0).map { $0?.rank } == [13, 13, 13, 13])
        // Four kings and the first queen gone: the first pile shows its jack, the others a queen.
        #expect(CascadeSimulation.remainingTops(f, launched: 5).map { $0?.rank } == [11, 12, 12, 12])
        #expect(CascadeSimulation.remainingTops(f, launched: 52).allSatisfy { $0 == nil })
    }

    /// A 4 × 4 test card: red on top, transparent underneath, so orientation shows.
    func topHalfRed() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 2, width: 4, height: 2))        // CG y-up: rows 2...3 are the top
        return ctx.makeImage()!
    }

    /// Red at (x, y) in the baked image (top-left origin).
    func isRed(_ image: CGImage, _ x: Int, _ y: Int) -> Bool {
        let data = image.dataProvider!.data! as Data
        let i = y * image.bytesPerRow + x * 4
        return data[i] > 200 && data[i + 3] > 200
    }

    @Test func trailBakesInBatchesAndTheRightWayUp() {
        let trail = TrailBitmap()
        trail.cards = [7: topHalfRed()]
        let stamps = [CascadeSimulation.Stamp(cardID: 7, center: CGPoint(x: 20, y: 30))]
        trail.bake(stamps, size: CGSize(width: 100, height: 100), displayScale: 1, final: false)
        #expect(trail.baked == 0 && trail.image == nil, "one stamp is not a batch yet")
        trail.bake(stamps, size: CGSize(width: 100, height: 100), displayScale: 1, final: true)
        let image = try! #require(trail.image)
        #expect(trail.baked == 1)
        #expect(isRed(image, 20, 29), "the card's top half is above its centre")
        #expect(!isRed(image, 20, 31), "and its bottom half is not red")
        #expect(!isRed(image, 80, 80), "nothing drawn elsewhere")
    }

    /// Resized mid-cascade: the bitmap is rebuilt at the new size from every stamp, not stretched.
    @Test func trailRebuildsAtANewSize() throws {
        let trail = TrailBitmap()
        trail.cards = [7: topHalfRed()]
        let stamps = [CascadeSimulation.Stamp(cardID: 7, center: CGPoint(x: 20, y: 30))]
        trail.bake(stamps, size: CGSize(width: 100, height: 100), displayScale: 1, final: true)
        trail.bake(stamps, size: CGSize(width: 200, height: 150), displayScale: 1, final: true)
        let image = try #require(trail.image)
        #expect(image.width == 200 && image.height == 150 && trail.size == CGSize(width: 200, height: 150))
        #expect(trail.baked == 1)
        #expect(isRed(image, 20, 29), "the stamp is where it was, at its own size")
    }

    /// A huge board's bitmap stays within its pixel budget; a normal one is full resolution.
    @Test func trailBitmapIsCappedOnHugeBoards() {
        #expect(TrailBitmap.bitmapScale(for: CGSize(width: 1000, height: 760), displayScale: 2) == 2)
        let huge = CGSize(width: 2560, height: 1300)
        let s = TrailBitmap.bitmapScale(for: huge, displayScale: 2)
        #expect(s < 2 && huge.width * s * huge.height * s <= TrailBitmap.maxPixels + 1)
    }

    /// Card images missing: nothing is baked (and nothing marked baked), so no stamp is lost.
    @Test func trailWaitsForTheCardImages() {
        let trail = TrailBitmap()
        let stamps = [CascadeSimulation.Stamp(cardID: 7, center: CGPoint(x: 20, y: 30))]
        trail.bake(stamps, size: CGSize(width: 100, height: 100), displayScale: 1, final: true)
        #expect(trail.baked == 0 && trail.image == nil)
    }

    @MainActor @Test func cardImagesArePreparedAheadAndKeptPerSize() async {
        let cards = fullFoundations().flatMap { $0 }
        let cache = CardImageCache()
        let style = CardStyle()
        #expect(cache.images(for: cards, width: 60, scale: 2, style: style) == nil)
        await cache.prepare(cards, width: 60, scale: 2, style: style)
        #expect(cache.images(for: cards, width: 60, scale: 2, style: style)?.count == 52)
        #expect(cache.images(for: cards, width: 80, scale: 2, style: style) == nil, "another size is another set")
        #expect(cache.images(for: cards, width: 60, scale: 2, style: CardStyle(face: .night, back: .artDeco)) == nil,
                "another card style is another set")
    }

    @Test(arguments: [
        // isWon, dismissed, cascadeFinished, reduceMotion, voiceOver -> shown
        (true, false, false, false, false, false),   // the cascade plays uncovered
        (true, false, true, false, false, true),     // ...then the sheet
        (true, false, false, true, false, true),     // Reduce Motion: no cascade, sheet at once
        (true, false, false, false, true, true),     // VoiceOver: sheet at once
        (true, true, true, false, false, false),     // closed: stays closed
        (false, false, true, true, true, false),     // not won
    ])
    func winSheetTiming(_ c: (Bool, Bool, Bool, Bool, Bool, Bool)) {
        #expect(ContentView.showsWinSheet(isWon: c.0, dismissed: c.1, cascadeFinished: c.2,
                                          reduceMotion: c.3, voiceOver: c.4) == c.5)
    }
}

/// Spec "Top row": the draw pile on the left (default) or the right, where the top row mirrors —
/// foundations in columns 0–3, waste 5, stock 6 — and the tableau stays put.
@Suite struct DrawPileSides {
    let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)

    /// A Draw 3 game with five cards on the waste: two buried, three fanned.
    func fiveOnTheWaste() -> GameState {
        var s = SolitaireEngine.newGame(drawCount: 3, seed: 4)
        s.waste = Array(s.stock.suffix(5)).map { var c = $0; c.isFaceUp = true; return c }
        s.stock.removeLast(5)
        return s
    }

    @Test func leftIsTheDefaultLayout() {
        let s = fiveOnTheWaste()
        #expect(BoardLayout(state: s, metrics: m) == BoardLayout(state: s, metrics: m, side: .left))
        let l = BoardLayout(state: s, metrics: m)
        #expect(l.slot(.stock).minX == m.columnX(0) && l.slot(.waste).minX == m.columnX(1))
        #expect((0..<4).allSatisfy { l.slot(.foundation($0)).minX == m.columnX(3 + $0) })
    }

    @Test func onTheRightTheTopRowMirrorsAndTheTableauStays() {
        let s = fiveOnTheWaste()
        let r = BoardLayout(state: s, metrics: m, side: .right)
        let l = BoardLayout(state: s, metrics: m, side: .left)
        #expect(r.slot(.stock).minX == m.columnX(6) && r.slot(.waste).minX == m.columnX(5))
        #expect((0..<4).allSatisfy { r.slot(.foundation($0)).minX == m.columnX($0) }, "foundation 1 leftmost")
        #expect([r.slot(.stock), r.slot(.waste)].allSatisfy { $0.minY == m.topRowY })
        let tableau = { (b: BoardLayout) in b.placements.filter { if case .tableau = $0.pile { true } else { false } } }
        #expect(tableau(r) == tableau(l), "the columns don't move")
    }

    /// On the right the playable card stays on the waste's slot, next to the stock; the two below
    /// it step left by 0.3 × width (so their corner index shows), and buried cards sit under the
    /// bottom of the fan. The fan stays inside the empty column, clear of the foundations.
    @Test func theDrawThreeFanOpensIntoTheEmptyColumn() {
        let s = fiveOnTheWaste()
        let step = m.cardWidth * 0.3
        let r = BoardLayout(state: s, metrics: m, side: .right)
        let rw = r.placements.filter { $0.pile == .waste }.sorted { $0.index < $1.index }
        let slot = r.slot(.waste).minX
        #expect(rw.map(\.frame.minX) == [slot - 2 * step, slot - 2 * step, slot - 2 * step, slot - step, slot])
        #expect(rw.map(\.isExposed) == [false, false, true, true, true])
        #expect(rw.allSatisfy { $0.frame.minX >= r.slot(.foundation(3)).maxX }, "clear of foundation 4")
        #expect(rw.last!.zIndex > rw[3].zIndex, "the playable card is on top")

        let l = BoardLayout(state: s, metrics: m, side: .left)
        let lw = l.placements.filter { $0.pile == .waste }.sorted { $0.index < $1.index }
        let lslot = l.slot(.waste).minX
        #expect(lw.map(\.frame.minX) == [lslot, lslot, lslot, lslot + step, lslot + 2 * step])
        #expect(lw.allSatisfy { $0.frame.maxX <= l.slot(.foundation(0)).minX }, "clear of foundation 1")
    }

    @Test func dropsLandOnTheMirroredFoundations() {
        let r = BoardLayout(state: fiveOnTheWaste(), metrics: m, side: .right)
        for f in 0..<4 {
            let slot = r.slot(.foundation(f))
            #expect(r.dropTarget(for: CGPoint(x: slot.midX, y: slot.midY)) == .foundation(f))
        }
    }

    @Test func anUnknownSavedSideReadsAsLeft() {
        #expect(DrawPileSide(rawValue: "sideways") == nil)
        #expect(DrawPileSide.allCases.map(\.rawValue) == ["left", "right"])
    }
}
