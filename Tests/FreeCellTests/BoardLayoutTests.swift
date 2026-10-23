import CoreGraphics
import Foundation
import SwiftUI
import Testing
import FreeCellEngine
@testable import FreeCell

/// The board area (inside safe areas and the header and bar) for the spec's layout acceptance
/// sizes. Derived from each device's points: screen − status bar/home indicator/side insets −
/// the header and bar.
enum BoardSize: String, CaseIterable {
    case iPhoneSEPortrait        // 375 × 667; status 20
    case iPhoneSELandscape       // 667 × 375
    case iPhoneProMaxLandscape   // 956 × 440; side insets 2 × 62, home 21
    case iPadThirdSplit          // 320-pt split column on an 11" iPad; status 24
    case mac600                  // the smallest Mac window (FreeCellApp.minimumWindow)

    /// The board's space on each: the screen less the header (48 pt) and bottom bar (60 pt buttons
    /// + 16), and any safe-area insets — on a phone held sideways, only the shorter bar the header
    /// folds into (52 + 16). The board runs edge to edge.
    var size: CGSize {
        let chrome: CGFloat = 48 + 76
        let landscapeChrome: CGFloat = 52 + 16
        return switch self {
        case .iPhoneSEPortrait: CGSize(width: 375, height: 667 - 20 - chrome)
        case .iPhoneSELandscape: CGSize(width: 667, height: 375 - landscapeChrome)
        case .iPhoneProMaxLandscape: CGSize(width: 956 - 124, height: 440 - 21 - landscapeChrome)
        case .iPadThirdSplit: CGSize(width: 320, height: 1180 - 24 - chrome)
        case .mac600: CGSize(width: FreeCellApp.minimumWindow.width, height: FreeCellApp.minimumWindow.height - chrome)
        }
    }

    var isTouch: Bool { self != .mac600 }
}

/// The tallest column the spec asks for: six cards under a full K→A run — nineteen — with every
/// free cell full.
func worstCaseState() -> GameState {
    let run = (1...13).reversed().map { rank in Card(suit: rank % 2 == 1 ? .spades : .hearts, rank: rank) }
    let used = Set(run)
    var rest = Suit.allCases.flatMap { s in (1...13).map { Card(suit: s, rank: $0) } }.filter { !used.contains($0) }
    let under = Array(rest.prefix(6)); rest.removeFirst(6)
    let cells: [Card?] = Array(rest.prefix(4)); rest.removeFirst(4)
    var columns: [[Card]] = [under + run]
    for t in 1..<8 {                                                  // the other 29: 5, then 4 each
        let take = t == 1 ? 5 : 4
        columns.append(Array(rest.prefix(take)))
        rest.removeFirst(take)
    }
    precondition(rest.isEmpty && columns.joined().count + 4 == 52)
    return GameState(cells: cells, foundations: [[], [], [], []], tableau: columns, number: 1)
}

@Suite struct Metrics {
    @Test func followsTheSpecRatios() {
        let m = BoardMetrics(size: CGSize(width: 700, height: 2000), isTouch: false)
        #expect(abs(m.gap - 700 * 0.018) < 0.001)
        #expect(abs(m.cardWidth - (700 - 9 * m.gap) / 8) < 0.001, "eight columns, seven gaps and two margins")
        #expect(abs(m.cardHeight - m.cardWidth * 1.4) < 0.001)
        #expect(abs(m.cornerRadius - m.cardWidth * 0.09) < 0.001)
        #expect(abs(m.fan - m.cardHeight * 0.29) < 0.001)
        #expect(!m.isCompressed)
    }

    @Test func boardWidthIsCappedAt900AndCentred() {
        let m = BoardMetrics(size: CGSize(width: 2000, height: 4000), isTouch: false)
        #expect(abs(m.cardWidth - (900 - 9 * 900 * 0.018) / 8) < 0.001)
        #expect(abs(m.leftEdge - (2000 - m.usedWidth) / 2) < 0.001)
    }

    @Test func wideBoardGapsNeverBelowFourPoints() {
        let m = BoardMetrics(size: CGSize(width: 520, height: 2000), isTouch: false)
        #expect(m.gap == 520 * 0.018 || m.gap == 4)
        #expect(m.gap >= 4 && m.margin == m.gap)
    }

    /// Phone-width boards use 3 pt gaps inside 4 pt margins, for bigger cards.
    @Test func narrowBoardsUseTightGutters() {
        let m = BoardMetrics(size: CGSize(width: 390, height: 640), isTouch: true)
        #expect(m.gap == 3 && m.margin == 4)
        #expect(abs(m.cardWidth - (390 - 2 * 4 - 7 * 3) / 8) < 0.001)
        #expect(abs(m.leftEdge - 4) < 0.001, "the outer columns sit 4 pt from the edges")
    }

    /// The space under the top row is 0.3 × card width, at most 16 pt.
    @Test(arguments: [CGSize(width: 390, height: 640), CGSize(width: 1000, height: 2000)])
    func rowGapIsThirtyPercentOfACardWidthAtMost16(_ size: CGSize) {
        let m = BoardMetrics(size: size, isTouch: false)
        #expect(abs(m.tableauY - (m.topRowY + m.cardHeight) - min(0.3 * m.cardWidth, 16)) < 0.001)
    }

    /// The smallest Mac window keeps cards at least 40 pt wide (eight columns and a twelve-card
    /// column to fit in 520 pt).
    @Test func theSmallestMacWindowKeepsCardsReadable() {
        #expect(BoardMetrics(size: BoardSize.mac600.size, isTouch: false).cardWidth >= 40)
    }

    /// The chip shows this game's number and Hard Core (spec "Layout and visuals").
    @Test func theGameChipShowsTheNumber() {
        #expect(GameHeader.gameChip(number: 24301) == ("#24301", "Game 24301"))
        #expect(GameHeader.gameChip(number: 24301, hardCore: true) == ("#24301 · HC", "Game 24301, Hard Core"))
        #expect(GameHeader.gameChip(number: 24301, relaxed: true) == ("#24301 · RX", "Game 24301, Relaxed"))
        #expect(GameHeader.gameChip(number: 24301, hardCore: true, relaxed: true) == ("#24301 · HC · RX", "Game 24301, Hard Core, Relaxed"))
    }

    /// On short, wide boards cards are capped so a twelve-card column keeps a readable fan; a fresh
    /// deal is never squeezed.
    @Test(arguments: [BoardSize.iPhoneProMaxLandscape, .iPhoneSELandscape, .mac600])
    func shortWideBoardsCapTheCardSizeByHeight(_ board: BoardSize) {
        let size = board.size
        let m = BoardMetrics(size: size, isTouch: board.isTouch)
        let byWidth = (min(size.width, 900) - 2 * m.margin - 7 * m.gap) / 8
        #expect(m.cardWidth < byWidth, "the height cap should bind here")
        #expect(m.fan(forColumnOf: 12) >= m.cardHeight * BoardMetrics.readableFanRatio - 0.01, "twelve stay readable")
        #expect(m.fan(forColumnOf: 13) < m.cardHeight * BoardMetrics.readableFanRatio, "…and the cap is no tighter")
        #expect(m.fan(forColumnOf: 7) == m.fan, "a fresh deal is not squeezed")
    }

    /// Where height is plentiful (portrait phones, iPads) the cap never binds: the width rule wins.
    @Test(arguments: [BoardSize.iPhoneSEPortrait, .iPadThirdSplit])
    func tallBoardsKeepTheWidthRule(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: board.isTouch)
        #expect(abs(m.cardWidth - (min(board.size.width, 900) - 2 * m.margin - 7 * m.gap) / 8) < 0.001)
    }

    /// Touch cards narrower than 44 pt widen their hit area to the whole column slot.
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
        #expect(m.fan(forColumnOf: 2) == m.fan)
        #expect(m.fan(forColumnOf: 19) < m.fan)
        #expect(m.fan(forColumnOf: 1) == m.fan && m.fan(forColumnOf: 0) == m.fan)
    }
}

@Suite struct TopRow {
    let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)

    /// Free cells in columns 1–4, foundations in 5–8 (spec "Top row").
    @Test func cellsLeftFoundationsRight() {
        let l = BoardLayout(state: FreeCellEngine.newGame(number: 617), metrics: m)
        for i in 0..<4 {
            #expect(l.slot(.cell(i)).minX == m.columnX(i) && l.slot(.cell(i)).minY == m.topRowY)
            #expect(l.slot(.foundation(i)).minX == m.columnX(4 + i) && l.slot(.foundation(i)).minY == m.topRowY)
        }
        #expect(l.cellCount == 4 && l.dropPiles.count == 4 + 4 + 8)
    }

    /// Hard Core has two cells: the other two slots are drawn closed and take no drops.
    @Test func hardCoreHasTwoOpenCells() {
        let l = BoardLayout(state: FreeCellEngine.newGame(number: 617, hardCore: true), metrics: m)
        #expect(l.cellCount == 2 && l.dropPiles.filter { if case .cell = $0 { true } else { false } }.count == 2)
    }

    /// A free cell's card sits on its cell.
    @Test func aCellsCardSitsOnIt() {
        var s = FreeCellEngine.newGame(number: 617)
        let moved = s.tableau[2].removeLast()
        s.cells[2] = moved
        let l = BoardLayout(state: s, metrics: m)
        #expect(l.placements.first { $0.card == moved }?.frame == l.slot(.cell(2)))
    }
}

/// Acceptance: the board lays out without clipping on iPhone SE portrait, iPhone Pro Max
/// landscape, iPad split view at one third, and a 600 pt wide Mac window — with a 19-card column.
@Suite struct NoClipping {
    @Test(arguments: BoardSize.allCases)
    func everyCardFitsTheBoard(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: board.isTouch)
        for (name, s) in [("deal", FreeCellEngine.newGame(number: 617)), ("worst", worstCaseState())] {
            let layout = BoardLayout(state: s, metrics: m)
            let bounds = CGRect(origin: .zero, size: board.size).insetBy(dx: -0.001, dy: -0.001)
            for p in layout.placements {
                #expect(bounds.contains(p.frame), "\(board) \(name): \(p.card.id) at \(p.frame)")
            }
            let topRowBottom = m.topRowY + m.cardHeight
            #expect(layout.placements.filter { if case .tableau = $0.pile { true } else { false } }
                .allSatisfy { $0.frame.minY >= topRowBottom }, "the top row and the columns never overlap")
        }
        #expect(m.cardWidth >= 28, "\(board): cards too small to read (\(m.cardWidth) pt)")
    }
}

/// Renders the real board at each acceptance size to PNGs for a human to look at (they are
/// written under the test host's temporary directory, whose path is printed).
@MainActor @Suite struct Snapshots {
    @Test(arguments: BoardSize.allCases)
    func renderBoard(_ board: BoardSize) throws {
        for (name, s) in [("deal", FreeCellEngine.newGame(number: 617)), ("worst", worstCaseState())] {
            let store = makeStore(at: s)
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
    @Test func movedCardsAreRaisedAboveEverything() {
        let store = makeStore(at: position(columns: [cards("KD 5H"), cards("6C"), cards("QS JH TS")]))
        #expect(store.tap(pile: .tableau(0), index: 1))
        let moved = card("5H")
        #expect(store.movedCardIDs.contains(moved.id))
        let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)
        let layout = BoardLayout(state: store.state, metrics: m, raised: store.movedCardIDs)
        let placed = layout.placements.first { $0.card == moved }!
        #expect(layout.placements.filter { !store.movedCardIDs.contains($0.card.id) }.allSatisfy { $0.zIndex < placed.zIndex })
    }

    /// Within every pile, later cards are always drawn above earlier ones — after a move, a new
    /// deal and a resume alike.
    @Test func cardsStayInOrderWithinEveryPile() {
        let store = makeStore()
        let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)
        func check(_ when: String) {
            let layout = BoardLayout(state: store.state, metrics: m, raised: store.movedCardIDs)
            for (pile, placed) in Dictionary(grouping: layout.placements, by: \.pile) {
                let z = placed.sorted { $0.index < $1.index }.map(\.zIndex)
                #expect(z == z.sorted() && Set(z).count == z.count, "\(when): \(pile) out of order")
            }
        }
        playAMove(store); check("move")
        store.newGame(); check("new deal")
        store.resume(from: worstCaseState()); check("resume")
    }

    @Test func theClockTickDoesNotLowerAMovingCard() {
        let store = makeStore()
        playAMove(store)
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

    /// Every column card is read (all are face up), with its column; only cards a tap would move
    /// are buttons.
    @Test func everyColumnCardIsReadAndOnlyMovableCardsAreButtons() {
        let s = FreeCellEngine.newGame(number: 617)
        let r = roles(s)
        #expect(s.tableau.flatMap { $0 }.allSatisfy { r[$0.id] != .hidden })
        #expect(r[s.tableau[0].last!.id]!.text == "\(CardView.spokenName(s.tableau[0].last!)), column 1")
        for t in 0..<8 {
            for (i, c) in s.tableau[t].enumerated() {
                let movable = FreeCellEngine.autoDestination(for: .tableau(t), index: i, in: s) != nil
                #expect(r[c.id]!.isButton == movable)
            }
        }
    }

    @Test func aFreeCellsCardSaysWhereItIs() {
        var s = FreeCellEngine.newGame(number: 617)
        let held = s.tableau[0].removeLast()
        s.cells[1] = held
        #expect(roles(s)[held.id]!.text == "\(CardView.spokenName(held)), free cell 2")
    }

    @Test func foundationTopIsNamedButNotAButton() {
        var s = FreeCellEngine.newGame(number: 617)
        let home = [Card(suit: .hearts, rank: 1), Card(suit: .hearts, rank: 2)]
        s.tableau = s.tableau.map { $0.filter { !home.contains($0) } }
        s.foundations[0] = home
        let r = roles(s)
        #expect(r[home[1].id] == .label("2 of Hearts, foundation 1"))
        #expect(r[home[0].id] == .hidden)
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
        [Suit.spades, .hearts, .diamonds, .clubs].map { s in (1...13).map { Card(suit: s, rank: $0) } }
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

