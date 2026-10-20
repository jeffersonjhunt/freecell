import SwiftUI
import Testing
@testable import Solitaire

/// Spec "Colours and dialogs": everything on the dark cards, and the accent on system sheets,
/// reads at 4.5:1 or better (the gold accent it replaces did not).
@MainActor @Suite struct DialogColours {
    private func luminance(_ c: Color, _ scheme: ColorScheme = .light) -> Double {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        let r = c.resolve(in: env)
        return 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722 * Double(r.linearBlue)
    }

    private func contrast(_ a: Color, _ b: Color, _ scheme: ColorScheme = .light) -> Double {
        let (x, y) = (luminance(a, scheme), luminance(b, scheme))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: [("title", DialogColors.title), ("body", DialogColors.body),
                      ("label", DialogColors.label), ("orange text", DialogColors.orangeText)])
    func cardTextReads(_ name: String, _ colour: Color) {
        #expect(contrast(colour, DialogColors.card) >= 4.5, "\(name) on the card")
    }

    @Test func theMainButtonReadsLikeFinish() {
        #expect(contrast(TableColors.onAccent, TableColors.accent) >= 4.5)
    }

    /// The accent colours system buttons (Done) and links: #B04800 on light sheets, #FF8A3D on dark.
    @Test func theAccentReadsInBothAppearances() {
        #expect(contrast(Color("AccentColor"), .white, .light) >= 4.5, "on a light sheet")
        #expect(contrast(Color("AccentColor"), Color(hex: 0x1C1C1E), .dark) >= 4.5, "on a dark sheet")
        #expect(contrast(Color("AccentColor"), Color(hex: 0xF2F2F7), .light) >= 4.5, "on a light grouped form")
    }
}

/// A card is modal: the game's menu commands stand down while either kind is up.
@MainActor @Suite struct CardsAreModal {
    @Test func eitherCardCounts() {
        let ui = AppUI()
        #expect(!ui.cardIsShowing)
        ui.pendingNewGame = NewGameRequest(drawCount: 1, switching: false)
        #expect(ui.cardIsShowing, "a question")
        ui.pendingNewGame = nil
        ui.showingWinCard = true
        #expect(ui.cardIsShowing, "the win card")
    }
}

@Suite struct QuestionLabels {
    @Test func theLabelSaysWhatTheQuestionIsAbout() {
        #expect(NewGameRequest(drawCount: 1, switching: false).kicker == "NEW GAME")
        #expect(NewGameRequest(drawCount: 3, switching: true).kicker == "DRAW 1 → DRAW 3")
        #expect(NewGameRequest(drawCount: 1, switching: true).kicker == "DRAW 3 → DRAW 1")
    }
}
