import Testing
@testable import Solitaire

@Suite struct Help {
    var text: String {
        HowToPlay.sections.map { ([$0.title] + $0.lines).joined(separator: "\n") }.joined(separator: "\n")
    }

    /// The help explains the whole game: the goal, the deal, every move the rules allow, the
    /// stock and both draw modes, winning and auto-finish, and saving.
    @Test func coversTheRules() {
        let titles = HowToPlay.sections.map(\.title)
        #expect(titles == ["Goal", "The deal", "Moves", "Scoring", "Hard Core", "The stock", "Controls", "Winning", "Saving"])
        for phrase in ["ace up to king", "opposite colour", "Empty column:** only a king",
                       "Back from a foundation", "turns over by itself", "Draw 3", "turn the waste back over",
                       "Auto-finish", "no losing", "resumes at the next launch"] {
            #expect(text.contains(phrase), "missing: \(phrase)")
        }
    }

    /// Arrows such as ↩ have an emoji form, which iOS shows as a coloured box; every one must carry
    /// the text-style selector (U+FE0E) so it looks like the key glyph it is.
    @Test func keyGlyphsNeverRenderAsEmoji() {
        for arrow in ["↩", "↪", "⏎"] {
            let bare = text.components(separatedBy: arrow).dropFirst().filter { !$0.hasPrefix("\u{FE0E}") }
            #expect(bare.isEmpty, "\(arrow) without U+FE0E")
        }
        #expect(text.contains("↩\u{FE0E}"), "the auto-finish shortcut is still described")
    }

    /// The stock and foundations are described where the draw pile setting puts them.
    @Test func followsTheDrawPileSide() {
        let text = { (side: DrawPileSide) in
            HowToPlay.sections(drawPile: side).flatMap(\.lines).joined(separator: "\n")
        }
        #expect(text(.left).contains("**stock** (top left)") && text(.left).contains("**A**, top right"))
        #expect(text(.right).contains("**stock** (top right)") && text(.right).contains("**A**, top left"))
    }

    /// Scoring is explained with the spec's numbers.
    @Test func explainsScoring() {
        let text = HowToPlay.sections.first { $0.title == "Scoring" }?.lines.joined() ?? ""
        for figure in ["**600**", "**+5**", "**+35**", "**−3**", "**−100**", "**1000**"] {
            #expect(text.contains(figure), "\(figure)")
        }
    }

    /// Hard Core is explained: its passes, the ✕, where to turn it on.
    @Test func explainsHardCore() {
        let text = HowToPlay.sections.first { $0.title == "Hard Core" }?.lines.joined() ?? ""
        #expect(text.contains("**one pass**") && text.contains("**three**") && text.contains("✕") && text.contains("**Settings**"))
    }

    /// Asking before ending a game can be turned off, and the help says so (spec "New games and the
    /// draw mode").
    @Test func saysAskingCanBeTurnedOff() {
        let controls = HowToPlay.sections.first { $0.title == "Controls" }!.lines.joined(separator: "\n")
        #expect(controls.contains("ask first (unless you've turned that off in Settings)"))
    }

    /// The resume switch is described where it actually is on this platform.
    @Test func pointsToThisPlatformsResumeSetting() {
        let saving = HowToPlay.sections.first { $0.title == "Saving" }!.lines.joined()
        #if os(macOS)
        #expect(saving.contains("Settings (⌘,)"))
        #else
        #expect(saving.contains("More ▸ Settings…") && !saving.contains("New Game"))
        #endif
    }

    /// …and this platform's controls, not the other's.
    @Test func describesThisPlatformsControls() {
        let controls = HowToPlay.sections.first { $0.title == "Controls" }!.lines.joined(separator: "\n")
        #if os(macOS)
        #expect(controls.contains("**Click**") && controls.contains("**Space**") && controls.contains("Settings (⌘,)")
                && controls.contains("**DRAW 1 / DRAW 3**"))
        #expect(!controls.contains("**Tap**"))
        #else
        #expect(controls.contains("**Tap**") && controls.contains("**DRAW 1 / DRAW 3**") && !controls.contains("Draw 1 or Draw 3"))
        #expect(!controls.contains("**Click**"))
        #endif
        #expect(controls.contains("wiggles") && controls.contains("foundation does nothing"))
    }
}
