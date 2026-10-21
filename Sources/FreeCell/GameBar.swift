import CoreText
import SwiftUI

/// Space Mono (SIL Open Font License; Resources/Fonts) for the header's figures — the One Off
/// Endeavors type. Registered at launch for this process only; should that ever fail,
/// `Font.custom` falls back to the system font.
enum AppFont {
    static let regular = "SpaceMono-Regular"
    static let bold = "SpaceMono-Bold"

    static func register() {
        for name in [regular, bold] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func mono(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle) -> Font {
        .custom(bold ? Self.bold : regular, size: size, relativeTo: style)
    }
}

/// Colours of the table's controls (direction A, from the One Off Endeavors palette).
enum TableColors {
    static let text = Color(red: 0.957, green: 0.945, blue: 0.925)          // #F4F1EC
    static let accent = Color(red: 0.8, green: 0.333, blue: 0)               // #CC5500, burnt orange
    static let onAccent = Color(red: 0.039, green: 0.039, blue: 0.039)       // #0A0A0A
}

/// Score, time, moves and the draw chip, over the board — the same on every platform, its edges in line
/// with the outer columns (`width`, the board's used width). `compact`: the smaller form that sits
/// inside the bar on a phone held sideways. The chip shows this game's draw mode and switches it.
struct GameHeader: View {
    let store: GameStore
    let ui: AppUI
    var width: CGFloat?
    var compact = false

    var body: some View {
        if compact {
            stats.foregroundStyle(TableColors.text).fixedSize()
        } else {
            stats
                .foregroundStyle(TableColors.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .frame(maxWidth: width ?? BoardMetrics.maxBoardWidth)
                .frame(maxWidth: .infinity)
        }
    }

    private var stats: some View {
        HStack(alignment: .bottom, spacing: compact ? 14 : 22) {
            stat("SCORE", "\(store.score)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Score \(store.score)")
                .accessibilityAddTraits(.isStaticText)
            stat("TIME", Self.clock(store.state.elapsed))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time \(Self.spokenClock(store.state.elapsed))")
                .accessibilityAddTraits(.isStaticText)
            stat("MOVES", "\(store.state.moveCount)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(store.state.moveCount) moves")
                .accessibilityAddTraits(.isStaticText)
            if !compact { Spacer(minLength: 8) }
            drawChip
        }
    }

    /// "DRAW 1" / "DRAW 3": a button that switches to the other mode by dealing a new game in it
    /// (asked first when a game is in progress). The capsule is 28 pt tall; its tap target reaches
    /// 8 pt beyond it above and below (44 pt) without making the header any taller.
    private var drawChip: some View {
        let chip = Self.drawChip(current: store.state.drawCount, hardCore: store.state.isHardCore)
        return Button { ui.requestNewGame(drawCount: chip.other, store: store) } label: {
            HStack(spacing: 6) {
                Text(chip.text)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.75)
            }
            .font(AppFont.mono(11, relativeTo: .caption2))
            .tracking(1.1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(TableColors.text.opacity(0.3)))
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipButtonStyle())
        .focusable(false)                                       // see ActionBar.buttons
        .padding(.vertical, -8)
        .accessibilityLabel(chip.spoken)
        .accessibilityHint(chip.hint)
        .accessibilityInputLabels([chip.text.capitalized, chip.spoken, "Draw mode"])   // Voice Control: "Draw 1" works
        .accessibilityIdentifier("drawChip")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.mono(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(TableColors.text.opacity(0.66))
            Text(value)
                .font(AppFont.mono(compact ? 17 : 20, bold: true, relativeTo: .title3))
        }
    }

    /// The chip for this game's draw mode (and Hard Core), and the mode it switches to.
    nonisolated static func drawChip(current: Int, hardCore: Bool = false)
        -> (text: String, spoken: String, hint: String, other: Int) {
        let other = current == 3 ? 1 : 3
        let word = { $0 == 3 ? "three" : "one" }
        return (hardCore ? "DRAW \(current) · HC" : "DRAW \(current)",
                hardCore ? "Draw \(word(current)), Hard Core" : "Draw \(word(current))",
                "Switches to Draw \(other) and starts a new game", other)
    }

    static func clock(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func spokenClock(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return "\(s / 60) minutes \(s % 60) seconds"
    }
}

/// The controls along the bottom, the same on every platform: Undo, Restart (only with Settings ▸
/// Restart button on), Finish (burnt orange
/// when auto-finish is available), New Game (deals at once in the same mode; asks first mid-game)
/// and More. Each is a 60 pt
/// tall target; on iPad and the Mac the row is centred, at most 560 pt wide. `withStats`: a phone
/// held sideways, where height is short — the header folds in on the left and the buttons are
/// 52 pt tall, which gives the cards back the header's height.
struct ActionBar: View {
    let store: GameStore
    let ui: AppUI
    var withStats = false
    @AppStorage(AppSettings.restartButtonKey, store: AppSettings.defaults) private var showsRestart = false

    var body: some View {
        HStack(spacing: 16) {
            if withStats {
                GameHeader(store: store, ui: ui, compact: true)
                Spacer(minLength: 0)
            }
            buttons.frame(maxWidth: withStats ? 480 : 560)
        }
        .padding(8)
        .padding(.horizontal, withStats ? 8 : 0)
        .frame(maxWidth: .infinity)
        .environment(\.barButtonHeight, withStats ? 52 : 60)
        .background { Color.black.opacity(0.3).ignoresSafeArea(edges: [.bottom, .horizontal]) }
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    /// Like cards, the controls never take keyboard focus (no focus ring; Space never presses a
    /// focused button instead of drawing): the keyboard reaches all of them through the menus —
    /// ⌘Z, ⌘↩, ⌘N, Game ▸ Draw Three, Help and Settings.
    private var buttons: some View {
        HStack(spacing: 4) {
            Button { store.undo() } label: { BarLabel(title: "Undo", symbol: "arrow.uturn.backward") }
                .disabled(!store.canUndo)                       // also off once the game is won
                .focusable(false)
            if showsRestart {
                Button { ui.requestRestart(store: store) } label: {
                    BarLabel(title: "Restart", symbol: "arrow.counterclockwise")
                }
                .disabled(!store.canRestart)                    // a fresh deal is already the start
                .accessibilityHint("Plays the same deal again from the start. A restarted game scores 0")
                .focusable(false)
            }
            Button { store.autoFinish() } label: { BarLabel(title: "Finish", symbol: "forward") }
                .buttonStyle(BarButtonStyle(prominent: store.canAutoFinish))
                .disabled(!store.canAutoFinish)
                .accessibilityLabel("Auto-finish")
                .accessibilityInputLabels(["Finish", "Auto-finish"])   // Voice Control: the visible word works
                .focusable(false)
            Button { ui.requestNewGame(store: store) } label: {
                BarLabel(title: "New Game", symbol: "plus.rectangle.on.rectangle")
            }
            .focusable(false)
            moreControl
                .focusable(false)
        }
        .buttonStyle(BarButtonStyle())
    }

    /// More opens a dark card of tiles: How to Play, Settings and About (spec "Settings, About
    /// and the More menu").
    private var moreControl: some View {
        Button { ui.showingMore = true } label: { BarLabel(title: "More", symbol: "ellipsis.circle") }
    }
}

extension EnvironmentValues {
    /// The bar buttons' height: 60 pt, or 52 pt in the shorter landscape bar (both ≥ 44 pt).
    @Entry var barButtonHeight: CGFloat = 60
}

/// An icon over a short label, filling its share of the bar.
struct BarLabel: View {
    let title: String
    let symbol: String
    @Environment(\.barButtonHeight) private var height

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(height: 26)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// The draw chip: dims while pressed, like the bar's buttons.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The bar's buttons: plain on the felt, burnt orange when prominent, dimmed when disabled.
struct BarButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .foregroundStyle(prominent ? TableColors.onAccent : TableColors.text)
            .background(shape.fill(prominent ? TableColors.accent
                                   : configuration.isPressed ? Color.white.opacity(0.12) : .clear))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.38)
            .contentShape(shape)
    }
}
