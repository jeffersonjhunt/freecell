import SwiftUI
import Testing
import SolitaireEngine
@testable import Solitaire

/// Spec "Card styles": every face and back draws, stays readable when fanned, and keeps red and
/// black apart; an unknown saved choice falls back to the default.
@MainActor @Suite struct CardStyles {
    /// Decision D1: a face-up card under another shows only its top 0.24 × card height (0.336 × card
    /// width). The index's baseline — its capitals' tops plus their real height in this platform's
    /// font — has to fall inside that strip, for every face.
    @Test(arguments: CardFaceStyle.allCases)
    func indexFitsTheNarrowestFannedStrip(_ face: CardFaceStyle) {
        let strip = BoardMetrics.readableFanRatio * BoardMetrics.aspect
        let spec = FaceSpec.of(face)
        #expect(spec.capHeight > spec.rankSize * 0.5, "\(face): cap height was measured (not 0)")
        let bottom = spec.indexBottom()
        #expect(bottom <= strip, "\(face): index reaches \(bottom) of the card width; the strip is \(strip)")
    }

    private func luminance(_ c: Color) -> Double {
        let r = c.resolve(in: EnvironmentValues())
        return 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722 * Double(r.linearBlue)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Red and black differ in lightness, not hue alone, and both read on the card (WCAG 4.5:1).
    @Test(arguments: CardFaceStyle.allCases)
    func inksAreDistinctAndReadable(_ face: CardFaceStyle) {
        let s = FaceSpec.of(face)
        #expect(contrast(s.red, s.black) >= 1.5, "\(face): red and black too alike")
        #expect(contrast(s.red, s.paper) >= 4.5, "\(face): red on paper")
        #expect(contrast(s.black, s.paper) >= 4.5, "\(face): black on paper")
    }

    /// The colour at a point of a card rendered in a style.
    private func pixel(_ card: Card, _ style: CardStyle, at p: CGPoint) -> (r: Int, g: Int, b: Int)? {
        let r = ImageRenderer(content: CardView(card: card, width: 100).environment(\.cardStyle, style))
        r.scale = 1
        guard let cg = r.cgImage, let data = cg.dataProvider?.data as Data? else { return nil }
        let bpp = cg.bitsPerPixel / 8
        let i = Int(p.y) * cg.bytesPerRow + Int(p.x) * bpp
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    private func near(_ px: (r: Int, g: Int, b: Int)?, _ hex: UInt32, _ tolerance: Int = 24) -> Bool {
        guard let px else { return false }
        let want = (Int(hex >> 16 & 0xFF), Int(hex >> 8 & 0xFF), Int(hex & 0xFF))
        return abs(px.r - want.0) <= tolerance && abs(px.g - want.1) <= tolerance && abs(px.b - want.2) <= tolerance
    }

    /// Each face paints its paper (sampled left of centre, clear of the index and the suit).
    @Test(arguments: [(CardFaceStyle.bigIndex, UInt32(0xFFFFFF)), (.vintage, 0xFBF4E4), (.night, 0x262626)])
    func facesPaintTheirPaper(_ face: CardFaceStyle, _ paper: UInt32) {
        let ace = Card(suit: .spades, rank: 1, isFaceUp: true)
        #expect(near(pixel(ace, CardStyle(face: face), at: CGPoint(x: 12, y: 70)), paper))
    }

    /// Each back paints its panel (sampled near the panel's corner, between pattern lines).
    @Test(arguments: [(CardBackStyle.burntOrange, UInt32(0xCC5500)), (.racingGreen, 0x1F5E3A), (.artDeco, 0x1B2A4A)])
    func backsPaintTheirPanel(_ back: CardBackStyle, _ panel: UInt32) {
        let down = Card(suit: .spades, rank: 1, isFaceUp: false)
        let style = CardStyle(back: back)
        // A few points on the panel; at least one falls between the pattern's lines.
        let points = [CGPoint(x: 50, y: 70), CGPoint(x: 52, y: 70), CGPoint(x: 50, y: 73), CGPoint(x: 55, y: 66)]
        #expect(points.contains { near(pixel(down, style, at: $0), panel, 30) })
    }

    /// A saved value the app doesn't know reads as no choice (the saved-setting path itself is
    /// covered by the UI test testUnknownSavedCardStyleFallsBackToTheDefault).
    @Test func unknownSavedStylesFallBack() {
        #expect(CardFaceStyle(rawValue: "fourColour") == nil)
        #expect(CardBackStyle(rawValue: "tartan") == nil)
        #expect(CardFaceStyle.allCases.map(\.rawValue) == ["classic", "bigIndex", "vintage", "night"])
        #expect(CardStyle() == CardStyle(face: .classic, back: .classicBlue), "the original look by default")
    }
}
