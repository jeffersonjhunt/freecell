import SwiftUI
import Testing
@testable import FreeCell

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

/// A card is modal: the game's menu commands stand down while any of them is up.
@MainActor @Suite struct CardsAreModal {
    @Test func everyCardCounts() {
        let ui = AppUI()
        #expect(!ui.cardIsShowing)
        ui.pendingNewGame = NewGameRequest()
        #expect(ui.cardIsShowing, "a question")
        ui.pendingNewGame = nil
        ui.choosingGame = true
        #expect(ui.cardIsShowing, "Choose a game")
        ui.choosingGame = false
        ui.showingWinCard = true
        #expect(ui.cardIsShowing, "the win card")
    }
}

@Suite struct QuestionLabels {
    @Test func theLabelSaysWhatTheQuestionIsAbout() {
        #expect(NewGameRequest().kicker == "NEW GAME")
        #expect(NewGameRequest(number: 617).kicker == "NEW GAME")
        #expect(NewGameRequest(hardCore: true, changesHardCore: true).kicker == "HARD CORE")
        #expect(NewGameRequest(relaxed: true, changesRelaxed: true).kicker == "RELAXED")
        #expect(NewGameRequest(number: 617, restarts: true).kicker == "RESTART")
    }
}
