import SwiftUI

/// The dark cards (spec "Colours and dialogs"): the win card and the "lose this game?" questions,
/// over the table dimmed by a black scrim. One look on every platform, replacing the system
/// sheet and alert, whose gold buttons were hard to read.
enum DialogColors {
    static let card = Color(hex: 0x141414)
    static let hairline = Color(hex: 0x2A2A2A)
    static let title = Color(hex: 0xF4F1EC)
    static let body = Color(hex: 0xC8C3BD)
    static let label = Color(hex: 0x9A9590)
    static let outline = Color(hex: 0x4A4642)
    /// Orange as text on the dark card (7.8:1); #CC5500 is for fills only.
    static let orangeText = Color(hex: 0xFF8A3D)
    static let scrim = Color.black.opacity(0.6)
}

/// A card's buttons: the main one orange with dark text (as Finish), the others outlined, and a
/// plain one for Close. Never keyboard-focused (like the bar): Return and Esc reach them.
struct DialogButtonStyle: ButtonStyle {
    enum Kind { case main, outlined, plain }
    var kind: Kind
    var height: CGFloat = 48
    /// Takes all the width it is offered; false: just its label's width (plus padding).
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            // Text styles, so the buttons follow Larger Text (17 / 16 pt at the default size).
            .font(kind == .main ? .headline.weight(.bold) : kind == .outlined ? .callout.weight(.semibold) : .callout)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(kind == .main ? TableColors.onAccent : kind == .plain ? DialogColors.body : DialogColors.title)
            .padding(.horizontal, fills ? 8 : 16)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: height)
            .background {
                switch kind {
                case .main: shape.fill(TableColors.accent)
                case .outlined: shape.strokeBorder(DialogColors.outline, lineWidth: 1)
                case .plain: Color.clear
                }
            }
            .contentShape(shape)
            #if os(iOS)
            .contentShape(.hoverEffect, shape)          // iPad pointer: the button's own shape lights
            .hoverEffect(.highlight)
            #endif
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// The dimmed table and a card on it. `bottom`: anchored to the bottom of the screen (the win
/// card on a phone held upright); otherwise centred, at most `maxWidth` wide. A tap on the dimmed
/// table calls `outside` (nil: the tap does nothing, but still never reaches the board).
struct DialogScrim<Card: View>: View {
    var bottom = false
    var maxWidth: CGFloat = 420
    var outside: (() -> Void)?
    @ViewBuilder let card: () -> Card

    var body: some View {
        ZStack(alignment: bottom ? .bottom : .center) {
            DialogColors.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { outside?() }
                .accessibilityHidden(true)
            card()
                .frame(maxWidth: bottom ? .infinity : maxWidth)
                .padding(bottom ? 12 : 24)
        }
    }
}

/// The card itself: #141414, hairline edge, large corners and a soft shadow. Modal for VoiceOver.
/// Its text follows Larger Text; when that makes it taller than the screen, it scrolls.
struct DialogCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    let identifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            stack
            ScrollView { stack }.scrollBounceBehavior(.basedOnSize)
        }
        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(DialogColors.card))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(DialogColors.hairline))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(identifier)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(EdgeInsets(top: 24, leading: 20, bottom: 18, trailing: 20))
    }
}

/// The small Space Mono label over a card's title ("NEW GAME", "DRAW 1").
struct DialogKicker: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.mono(11, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(DialogColors.label)
    }
}

/// "Start a new game?" and the like: a label, the title, the message, then Cancel and the
/// confirming button (spec "Colours and dialogs").
struct QuestionCard: View {
    let request: NewGameRequest
    let cancel: () -> Void
    let confirm: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        DialogCard(identifier: "confirmation") {
            DialogKicker(text: request.kicker)
            Text(request.title)
                .font(.title2.bold())
                .foregroundStyle(DialogColors.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(request.message)
                .font(.callout)
                .foregroundStyle(DialogColors.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Cancel", action: cancel)
                    .buttonStyle(DialogButtonStyle(kind: .outlined))
                    .keyboardShortcut(.cancelAction)
                Button(request.confirm, action: confirm)
                    .buttonStyle(DialogButtonStyle(kind: .main))
                    .keyboardShortcut(.defaultAction)
            }
            .focusable(false)
            .padding(.top, 8)
        }
        .onAppear { titleFocused = true }
    }
}

/// The win card: the draw mode, "You won!", the figures in Space Mono, then a new game in the
/// same mode (orange), the other mode, and Close. `wide`: one row of buttons (iPad, the Mac, a
/// phone held sideways); otherwise stacked for a phone held upright.
struct WinCard: View {
    let drawCount: Int
    var hardCore = false
    let score: Int
    /// The score's two parts: what the play earned and the time bonus (spec "Scoring").
    var playScore = 0
    var timeBonus = 0
    let moves: Int
    let elapsed: TimeInterval
    let passes: Int
    let undos: Int
    /// The win's place in its mode's Top 10, if it made the list.
    var topTenRank: Int?
    var wide = false
    var showTopTen: () -> Void = {}
    let newGame: (Int) -> Void
    let close: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    private var other: Int { drawCount == 3 ? 1 : 3 }

    var body: some View {
        DialogCard(cornerRadius: wide ? 24 : 28, identifier: "winCard") {
            VStack(spacing: 6) {
                DialogKicker(text: hardCore ? "DRAW \(drawCount) · HARD CORE" : "DRAW \(drawCount)")
                Text("You won!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(DialogColors.title)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Text("SCORE")
                    .font(AppFont.mono(11, relativeTo: .caption2))
                    .tracking(1.5)
                    .foregroundStyle(DialogColors.label)
                Text(verbatim: "\(score)")
                    .font(AppFont.mono(wide ? 52 : 60, bold: true, relativeTo: .largeTitle))
                    .foregroundStyle(DialogColors.title)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(verbatim: "PLAY \(playScore) + TIME BONUS \(timeBonus)")
                    .font(AppFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(DialogColors.body)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score \(score)")
            .accessibilityValue("play \(playScore) plus time bonus \(timeBonus)")
            if let topTenRank {
                Text("New Top 10 · #\(topTenRank) in Draw \(drawCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DialogColors.orangeText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(DialogColors.orangeText))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("topTenBadge")
            }
            HStack(spacing: 8) {
                figure("MOVES", "\(moves)", spoken: "\(moves) moves")
                figure("TIME", GameHeader.clock(elapsed), spoken: "Time \(GameHeader.spokenClock(elapsed))")
                figure("PASSES", "\(passes)", spoken: passes == 1 ? "1 pass" : "\(passes) passes")
                figure("UNDOS", "\(undos)", spoken: undos == 1 ? "1 undo" : "\(undos) undos")
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { DialogColors.hairline.frame(height: 1) }
            .overlay(alignment: .bottom) { DialogColors.hairline.frame(height: 1) }
            .padding(.vertical, 6)
            buttons
        }
        .onAppear { titleFocused = true }
    }

    private func figure(_ label: String, _ value: String, spoken: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(AppFont.mono(11, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(DialogColors.label)
            Text(value)
                .font(AppFont.mono(20, bold: true, relativeTo: .title3))
                .foregroundStyle(DialogColors.title)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var buttons: some View {
        let same = Button("New Game · Draw \(drawCount)") { newGame(drawCount) }
            .buttonStyle(DialogButtonStyle(kind: .main, height: wide ? 44 : 54))
            .keyboardShortcut(.defaultAction)
        // In one row the main button gets whatever its neighbours leave, so its label is never cut.
        let switchMode = Button("Draw \(other) instead") { newGame(other) }
            .buttonStyle(DialogButtonStyle(kind: .outlined, height: wide ? 44 : 48, fills: !wide))
        let closeButton = Button("Close", action: close)
            .buttonStyle(DialogButtonStyle(kind: wide ? .outlined : .plain, height: 44, fills: !wide))
            .keyboardShortcut(.cancelAction)
        let topTen = Button("Top 10", action: showTopTen)
            .buttonStyle(DialogButtonStyle(kind: .outlined, height: wide ? 44 : 48, fills: !wide))
        Group {
            if wide {
                HStack(spacing: 8) { closeButton; topTen; switchMode; same }
            } else {
                VStack(spacing: 10) {
                    same
                    HStack(spacing: 10) { switchMode; topTen }
                    closeButton
                }
            }
        }
        .focusable(false)
    }
}

/// More (spec "Settings, About and the More menu"): a dark card of tiles — icon over label, like
/// the bar's buttons — that opens How to Play, Scores, Settings or About and closes itself. On a phone
/// held upright it rises from the bottom; elsewhere it is centred.
struct MoreCard: View {
    let ui: AppUI
    var showScores: () -> Void = {}
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    #endif
    @AccessibilityFocusState private var labelFocused: Bool

    var body: some View {
        DialogCard(cornerRadius: 28, identifier: "moreCard") {
            DialogKicker(text: "MORE")
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($labelFocused)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile("How to Play", symbol: "questionmark.circle") { open(.help) }
                    tile("Scores", symbol: "trophy") { ui.showingMore = false; showScores() }
                }
                GridRow {
                    tile("Settings", symbol: "gearshape") { open(.settings) }
                    tile("About", symbol: "info.circle") { open(.about) }
                }
            }
            Button("Close") { ui.showingMore = false }
                .buttonStyle(DialogButtonStyle(kind: .plain, height: 44))
                .keyboardShortcut(.cancelAction)
                .focusable(false)
        }
        .onAppear { labelFocused = true }
    }

    private enum Destination { case help, settings, about }

    private func open(_ destination: Destination) {
        ui.showingMore = false
        #if os(macOS)
        switch destination {
        case .help: openWindow(id: HelpCommands.windowID)
        case .settings: openSettings()
        case .about: openWindow(id: AboutCommands.windowID)
        }
        #else
        switch destination {
        case .help: ui.showingHelp = true
        case .settings: ui.showingSettings = true
        case .about: ui.showingAbout = true
        }
        #endif
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(DialogColors.orangeText)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DialogColors.title)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
        }
        .buttonStyle(TileButtonStyle())
        .focusable(false)
    }
}

/// A More tile: #1E1E1E with the card's hairline, dimming while pressed.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .background(shape.fill(Color(hex: 0x1E1E1E)))
            .overlay(shape.strokeBorder(DialogColors.hairline))
            .contentShape(shape)
            #if os(iOS)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
            #endif
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
