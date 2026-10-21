import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The card faces the player can choose (spec "Card styles").
enum CardFaceStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, bigIndex, vintage, night

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: "Classic"
        case .bigIndex: "Big Index"
        case .vintage: "Vintage"
        case .night: "Night"
        }
    }
}

/// The card backs the player can choose (spec "Card styles").
enum CardBackStyle: String, CaseIterable, Identifiable, Sendable {
    case classicBlue, burntOrange, racingGreen, artDeco

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classicBlue: "Classic Blue"
        case .burntOrange: "Burnt Orange"
        case .racingGreen: "Racing Green"
        case .artDeco: "Art Deco"
        }
    }
}

/// The chosen face and back. Defaults are the original look.
struct CardStyle: Hashable, Sendable {
    var face: CardFaceStyle = .classic
    var back: CardBackStyle = .classicBlue
}

extension EnvironmentValues {
    /// Every card view draws in this style; the app sets it from the saved settings.
    @Entry var cardStyle = CardStyle()
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// How a face draws. Sizes are fractions of the card width.
struct FaceSpec: Sendable {
    enum Pip: Sendable { case corner, center }

    let face: CardFaceStyle
    let rankSize: CGFloat
    let rankWeight: Font.Weight
    let rankDesign: Font.Design
    let suitSize: CGFloat
    let pipSize: CGFloat
    let pip: Pip
    let paper: Color
    let border: Color
    let red: Color
    let black: Color
    let frame: Color?

    /// The corner index's capital tops sit this far below the card's top edge — the same margin
    /// as at its left — and the whole index stays inside the narrowest fanned strip
    /// (`BoardMetrics.readableFanRatio`; decision D1). Placing it by its capitals matters: text's
    /// built-in space above them would otherwise push it ~0.09 × width further down.
    static let indexTop: CGFloat = 0.07
    static let indexLeading: CGFloat = 0.07

    static func of(_ face: CardFaceStyle) -> FaceSpec {
        switch face {
        case .classic:
            FaceSpec(face: .classic, rankSize: 0.36, rankWeight: .semibold, rankDesign: .rounded, suitSize: 0.28, pipSize: 0.62,
                     pip: .corner, paper: Color("CardFace"), border: .black.opacity(0.25),
                     red: Color("CardRed"), black: Color("CardBlack"), frame: nil)
        case .bigIndex:
            FaceSpec(face: .bigIndex, rankSize: 0.37, rankWeight: .black, rankDesign: .default, suitSize: 0.30, pipSize: 0.66,
                     pip: .center, paper: .white, border: .black.opacity(0.25),
                     red: Color(hex: 0xD0021B), black: .black, frame: nil)
        case .vintage:
            FaceSpec(face: .vintage, rankSize: 0.36, rankWeight: .bold, rankDesign: .serif, suitSize: 0.28, pipSize: 0.6,
                     pip: .center, paper: Color(hex: 0xFBF4E4), border: Color(hex: 0x503C1E, opacity: 0.35),
                     red: Color(hex: 0x9E1B32), black: Color(hex: 0x1F1F1F), frame: Color(hex: 0x785A28, opacity: 0.45))
        case .night:
            FaceSpec(face: .night, rankSize: 0.36, rankWeight: .semibold, rankDesign: .rounded, suitSize: 0.28, pipSize: 0.62,
                     pip: .corner, paper: Color(hex: 0x262626), border: Color(hex: 0x3A3A3A),
                     red: Color(hex: 0xFF7A7A), black: Color(hex: 0xEDEAE4), frame: nil)
        }
    }

    /// The rank's cap height as a fraction of the card width, from this platform's font. Measured
    /// once per face: cap height scales with size, and cards redraw often (52 a frame in a drag).
    var capHeight: CGFloat { Self.capHeights[self.face] ?? 0 }

    /// Where the index's baseline falls, as a fraction of the card width: its top inset plus the
    /// rank font's real cap height on this platform.
    func indexBottom() -> CGFloat { Self.indexTop + capHeight }

    private static let capHeights: [CardFaceStyle: CGFloat] = Dictionary(uniqueKeysWithValues:
        CardFaceStyle.allCases.map { face in
            let s = of(face)
            return (face, CardFonts.capHeight(size: s.rankSize, weight: s.rankWeight, design: s.rankDesign))
        })
}

/// How a back draws: a card of `paper` with a patterned panel inset by 7 % of the width.
struct BackSpec: Sendable {
    enum Pattern: Sendable { case lattice, diamonds, rays }

    let paper: Color
    let panel: Color
    let pattern: Pattern
    let ink: Color
    let frame: Color?

    static func of(_ back: CardBackStyle) -> BackSpec {
        switch back {
        case .classicBlue:
            BackSpec(paper: Color("CardFace"), panel: Color("CardBack"), pattern: .lattice,
                     ink: Color("CardFace").opacity(0.35), frame: nil)
        case .burntOrange:
            BackSpec(paper: Color("CardFace"), panel: Color(hex: 0xCC5500), pattern: .lattice,
                     ink: .white.opacity(0.35), frame: nil)
        case .racingGreen:
            BackSpec(paper: Color(hex: 0xF7F1E3), panel: Color(hex: 0x1F5E3A), pattern: .diamonds,
                     ink: Color(hex: 0xF7F1E3, opacity: 0.35), frame: Color(hex: 0xF7F1E3, opacity: 0.8))
        case .artDeco:
            BackSpec(paper: Color(hex: 0xF7F1E3), panel: Color(hex: 0x1B2A4A), pattern: .rays,
                     ink: Color(hex: 0xC9A227, opacity: 0.75), frame: Color(hex: 0xC9A227))
        }
    }
}

/// The platform's font metrics for the system font, so the index can be placed by its capitals.
enum CardFonts {
    /// Cap height of the system font at `size` (any unit: a fraction of the card width in, the
    /// same fraction out).
    nonisolated static func capHeight(size: CGFloat, weight: Font.Weight, design: Font.Design) -> CGFloat {
        let reference: CGFloat = 100
        #if canImport(UIKit)
        var font = UIFont.systemFont(ofSize: reference, weight: uiWeight(weight))
        if let d = font.fontDescriptor.withDesign(uiDesign(design)) { font = UIFont(descriptor: d, size: reference) }
        return font.capHeight / reference * size
        #else
        var font = NSFont.systemFont(ofSize: reference, weight: nsWeight(weight))
        if let d = font.fontDescriptor.withDesign(nsDesign(design)), let f = NSFont(descriptor: d, size: reference) {
            font = f
        }
        return font.capHeight / reference * size
        #endif
    }

    #if canImport(UIKit)
    nonisolated private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .black: .black
        case .heavy: .heavy
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
    }

    nonisolated private static func uiDesign(_ d: Font.Design) -> UIFontDescriptor.SystemDesign {
        switch d {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: .default
        }
    }
    #else
    nonisolated private static func nsWeight(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .black: .black
        case .heavy: .heavy
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
    }

    nonisolated private static func nsDesign(_ d: Font.Design) -> NSFontDescriptor.SystemDesign {
        switch d {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: .default
        }
    }
    #endif
}
