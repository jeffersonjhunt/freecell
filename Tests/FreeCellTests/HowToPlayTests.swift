import Testing
@testable import FreeCell

@Suite struct Help {
    var text: String {
        HowToPlay.sections.map { ([$0.title] + $0.lines).joined(separator: "\n") }.joined(separator: "\n")
    }

    func section(_ title: String) -> String {
        HowToPlay.sections.first { $0.title == title }?.lines.joined(separator: "\n") ?? ""
    }

    /// The help explains the whole game: the goal, the deal and game numbers, every move the rules
    /// allow (the run limit included), playing cards home, ranking by time, Hard Core, Finish, saving.
    @Test func coversTheRules() {
        #expect(HowToPlay.sections.map(\.title) == ["Goal", "The deal", "Moves", "Playing cards home", "Your best",
                                                    "Hard Core", "Controls", "Winning", "Saving"])
        for phrase in ["ace up to king", "eight columns", "free cells", "1 to 1,000,000", "Microsoft",
                       "opposite colour", "empty column", "(empty free cells + 1) × 2 for each empty column",
                       "half that", "stay there", "aces and twos", "**time**", "fewer **moves**",
                       "**Two free cells**", "**Finish**", "resumes at the next launch"] {
            #expect(text.contains(phrase), "missing: \(phrase)")
        }
        for klondike in ["stock", "waste", "Draw 3", "redeal", "+5"] {
            #expect(!text.lowercased().contains(klondike.lowercased()), "left over from Klondike: \(klondike)")
        }
    }

    /// Arrows such as ↩ have an emoji form, which iOS shows as a coloured box; every one must carry
    /// the text-style selector (U+FE0E) so it looks like the key glyph it is.
    @Test func keyGlyphsNeverRenderAsEmoji() {
        for arrow in ["↩", "↪", "⏎"] {
            let bare = text.components(separatedBy: arrow).dropFirst().filter { !$0.hasPrefix("\u{FE0E}") }
            #expect(bare.isEmpty, "\(arrow) without U+FE0E")
        }
        #expect(text.contains("↩\u{FE0E}"), "the Finish shortcut is still described")
    }

    /// Automatic plays can be turned off, and the help says where.
    @Test func saysAutomaticPlaysCanBeTurnedOff() {
        #expect(section("Playing cards home").contains("Turn this off in **Settings**"))
    }

    /// Asking before ending a game can be turned off, and the help says so (spec "New games").
    @Test func saysAskingCanBeTurnedOff() {
        #expect(section("Controls").contains("asks first (unless you've turned that off in Settings)"))
    }

    /// The resume switch is described where it actually is on this platform.
    @Test func pointsToThisPlatformsResumeSetting() {
        let saving = section("Saving")
        #if os(macOS)
        #expect(saving.contains("Settings (⌘,)"))
        #else
        #expect(saving.contains("More ▸ Settings…") && !saving.contains("New Game"))
        #endif
    }

    /// …and this platform's controls, not the other's.
    @Test func describesThisPlatformsControls() {
        let controls = section("Controls")
        #if os(macOS)
        #expect(controls.contains("**Click**") && controls.contains("⇧⌘N") && controls.contains("Settings (⌘,)"))
        #expect(!controls.contains("**Tap**"))
        #else
        #expect(controls.contains("**Tap**") && controls.contains("game number"))
        #expect(!controls.contains("**Click**"))
        #endif
        #expect(controls.contains("wiggles") && controls.contains("**Restart**"))
    }
}
