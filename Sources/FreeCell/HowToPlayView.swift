import SwiftUI

/// The in-app help: the rules of Klondike and this platform's controls. On the Mac it is the
/// Help ▸ FreeCell Help window (⌘?); on iPhone and iPad a sheet opened from More ▸ How to Play
/// or, with a keyboard, the Help menu. The same content as the README's "How to play".
struct HowToPlayView: View {
    var done: (() -> Void)?

    var body: some View {
        ScrollView {
            HowToPlayContent()
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("How to Play")
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }
}

/// The sections themselves, without the scroll view (so they can also be rendered to an image).
struct HowToPlayContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(HowToPlay.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.lines, id: \.self) { line in
                        Text(.init(line))                          // Markdown: **bold** keys
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The help text, kept as data so a test can check it covers the rules and this platform's
/// controls.
enum HowToPlay {
    struct Section: Identifiable {
        let title: String
        let lines: [String]
        var id: String { title }
    }

    static var sections: [Section] {
        [
            Section(title: "Goal", lines: [
                "Move all 52 cards onto the four **foundations** (top right, marked **A**) — one pile per suit, from ace up to king.",
            ]),
            Section(title: "The deal", lines: [
                "Every card is dealt face up into **eight columns** — four of seven cards, four of six. Top left are four **free cells**, each holding one card.",
                "Every game has a **number** (top right of the header, **#24301**). Tap it to play any game from 1 to 1,000,000: the numbers are Microsoft's, so game 617 here is game 617 in any FreeCell.",
            ]),
            Section(title: "Moves", lines: [
                "**To a foundation:** an ace onto an empty foundation, then the same suit one rank higher.",
                "**Between columns:** the last card of a column (or a free cell's card) onto a card one rank higher of the opposite colour — a red 7 onto a black 8. Any card can go into an empty column.",
                "**To a free cell:** the last card of a column, into an empty cell.",
                "**Runs:** a run in order at the end of a column moves together if your free spaces could carry it card by card: **(empty free cells + 1) × 2 for each empty column**. Into an empty column, half that.",
                "Cards on a foundation stay there.",
            ]),
            Section(title: "Playing cards home", lines: [
                "A card no other card could still need goes to its foundation by itself: aces and twos, and any card once both foundations of the other colour are one rank behind. Turn this off in **Settings** to place every card yourself.",
            ]),
            Section(title: "Your best", lines: [
                "There are no points: wins rank by **time**, then by fewer **moves**. A run moved together is one move; cards the game plays home cost none.",
                "Your **Top 10** keeps the ten fastest wins, and Game Center has a leaderboard for normal games and one for Hard Core.",
            ]),
            Section(title: "Hard Core", lines: [
                "**Two free cells** instead of four — fewer games can be won. Turn it on in **Settings**; changing it starts a new game.",
            ]),
            Section(title: "Controls", lines: controls),
            Section(title: "Winning", lines: [
                "When every column is in order, **Finish** plays the rest home.",
                "Almost every game can be won (of the first million numbers, eight can't). If you're stuck, undo or start again. Once you win, the game is locked.",
            ]),
            Section(title: "Saving", lines: [
                "Your game is saved as you play and resumes at the next launch (undo starts fresh). \(resumeSetting)",
            ]),
        ]
    }

    /// Where the resume-at-launch switch lives on this platform.
    private static var resumeSetting: String {
        #if os(macOS)
        "You can turn resuming off in **Settings (⌘,)**."
        #else
        "You can turn resuming off in **More ▸ Settings…**."
        #endif
    }

    private static var controls: [String] {
        #if os(macOS)
        [
            "**Click** a card to send it to its best spot (double-click works too); **drag** to place it exactly. A card with nowhere to go wiggles.",
            "The bar along the bottom: **Undo**, **Finish** (once every column is in order), **New Game** (a random game) and **More** (How to Play, Scores, Settings and About).",
            "Click the game number at the top, or **File ▸ Choose Game… (⇧⌘N)**, to play a game by number. Mid-game, **New Game** asks first (unless you've turned that off in Settings).",
            "**⌘Z** undo · **⌘N** new game · **⇧⌘N** choose a game · **⌘↩\u{FE0E}** finish · **Settings (⌘,)**.",
            "Turn on **Restart button** in Settings and **Restart** (or **⌘R**) plays this game again from the start. A restarted game doesn't count toward your Top 10, your wins or Game Center.",
        ]
        #else
        [
            "**Tap** a card to send it to its best spot; **drag** to place it exactly. A card with nowhere to go wiggles.",
            "The bar along the bottom: **Undo**, **Finish** (once every column is in order), **New Game** (a random game) and **More** (How to Play, Scores, Settings and About).",
            "Tap the game number at the top to play a game by number. Mid-game, **New Game** asks first (unless you've turned that off in Settings).",
            "With a keyboard: **⌘Z** undo · **⌘N** new game · **⇧⌘N** choose a game · **⌘↩\u{FE0E}** finish.",
            "Turn on **Restart button** in Settings and **Restart**, beside Undo, plays this game again from the start. A restarted game doesn't count toward your Top 10, your wins or Game Center.",
        ]
        #endif
    }
}

#Preview {
    NavigationStack { HowToPlayView() }
}
