import SwiftUI

/// The in-app help: the rules of Klondike and this platform's controls. On the Mac it is the
/// Help ▸ Solitaire Help window (⌘?); on iPhone and iPad a sheet opened from More ▸ How to Play
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
    @AppStorage(AppSettings.drawPileSideKey, store: AppSettings.defaults) private var drawPileSide = DrawPileSide.left

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(HowToPlay.sections(drawPile: drawPileSide)) { section in
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

    /// With the draw pile on the left (the default).
    static var sections: [Section] { sections(drawPile: .left) }

    /// Where the stock and foundations are follows the draw pile setting (spec "Top row").
    static func sections(drawPile: DrawPileSide) -> [Section] {
        let (stock, foundations) = drawPile == .left ? ("top left", "top right") : ("top right", "top left")
        return [
            Section(title: "Goal", lines: [
                "Move all 52 cards onto the four foundations (marked **A**, \(foundations)) — one pile per suit, from ace up to king.",
            ]),
            Section(title: "The deal", lines: [
                "Seven columns: the first has one card, the seventh has seven. Only the last card of each column is face up.",
                "The other 24 cards are the **stock** (\(stock)). Cards you draw go face up on the **waste** beside it. (Settings can put this draw pile on either side.)",
            ]),
            Section(title: "Moves", lines: [
                "**To a foundation:** an ace onto an empty foundation, then the same suit one rank higher. Cards go up from the waste or the bottom of a column.",
                "**Between columns:** onto a card one rank higher of the opposite colour — a red 7 onto a black 8. A face-up run moves together.",
                "**Empty column:** only a king, with any run on it.",
                "**Back from a foundation:** drag its top card onto a column, under the same colour and rank rule.",
                "A face-down card uncovered at the bottom of a column turns over by itself.",
            ]),
            Section(title: "Scoring", lines: [
                "Every game starts at **0**: **+5** for each card on a foundation and **+35** for each finished suit; **−3** for each undo and **−100** for each pass through the deck after the first. The score never goes below 0.",
                "Win, and a **time bonus** is added: **600**, less 1 point a second in the second minute, 2 in the third, and so on — gone by 5:00. A one-pass win in under a minute scores **1000**.",
            ]),
            Section(title: "Hard Core", lines: [
                "A harder game: **one pass** through the deck in Draw 1, **three** in Draw 3. When they're used up the stock shows ✕. Turn it on in **Settings** — changing it starts a new game.",
            ]),
            Section(title: "The stock", lines: [
                "Draw one card, or three in **Draw 3** mode — then only the top card of the waste can be played.",
                "When the stock is empty, draw again to turn the waste back over. There is no limit.",
            ]),
            Section(title: "Controls", lines: controls),
            Section(title: "Winning", lines: [
                "When the stock and waste are empty and every card is face up, **Auto-finish** appears and plays the rest.",
                "There is no losing: if you are stuck, undo or deal again. Once you win, the game is locked.",
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
            "**Click** a card to send it to its best spot (double-click works too); **drag** to place it exactly.",
            "**Click the stock** or press **Space** to draw.",
            "The bar along the bottom: **Undo**, **Finish** (auto-finish, once every card can go home), **New Game** and **More** (How to Play, Settings — with the card faces and backs — and About).",
            "**DRAW 1 / DRAW 3** at the top switches mode by starting a new game (so does **Game ▸ Draw Three**). Mid-game, it and **New Game** ask first (unless you've turned that off in Settings).",
            "**⌘Z** undo · **⌘N** new game · **⌘↩\u{FE0E}** auto-finish · **File ▸ New Game: Draw 1 / Draw 3** · **Settings (⌘,)**.",
            "Turn on **Restart button** in Settings and **Restart** (or **⌘R**) plays the same deal again from the start. A restarted game scores 0 and doesn't count toward your Top 10 or Game Center.",
            "A card with nowhere to go wiggles. Clicking a card on a foundation does nothing — drag it if you mean to.",
        ]
        #else
        [
            "**Tap** a card to send it to its best spot; **drag** to place it exactly.",
            "**Tap the stock** to draw.",
            "The bar along the bottom: **Undo**, **Finish** (auto-finish, once every card can go home), **New Game** (same draw mode) and **More** (How to Play, Settings — with the card faces and backs — and About).",
            "Tap **DRAW 1 / DRAW 3** at the top to switch mode — that starts a new game. Mid-game, it and **New Game** ask first (unless you've turned that off in Settings).",
            "With a keyboard: **⌘Z** undo · **⌘N** new game · **Space** draw · **⌘↩\u{FE0E}** auto-finish.",
            "Turn on **Restart button** in Settings and **Restart**, beside Undo, plays the same deal again from the start. A restarted game scores 0 and doesn't count toward your Top 10 or Game Center.",
            "A card with nowhere to go wiggles. Tapping a card on a foundation does nothing — drag it if you mean to.",
        ]
        #endif
    }
}

#Preview {
    NavigationStack { HowToPlayView() }
}
