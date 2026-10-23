import SwiftUI
import FreeCellEngine

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

/// The small Space Mono label over a card's title ("NEW GAME", "GAME 617").
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

/// The win card (spec "Colours and dialogs", from the mockups): the game number, "You won!", the
/// time large in Space Mono with the moves under it, the Top 10 badge, then UNDOS, FREE CELLS and
/// WINS, and New Game (orange), Choose a game, Top 10 and Close. `wide`: one row of buttons (iPad,
/// the Mac, a phone held sideways); otherwise stacked for a phone held upright.
struct WinCard: View {
    let number: Int
    var hardCore = false
    var relaxed = false
    let moves: Int
    let elapsed: TimeInterval
    let undos: Int
    let freeCells: Int
    let wins: Int
    /// The win's place in the Top 10, if it made the list.
    var topTenRank: Int?
    var wide = false
    var showTopTen: () -> Void = {}
    let newGame: () -> Void
    let chooseGame: () -> Void
    let close: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        DialogCard(cornerRadius: wide ? 24 : 28, identifier: "winCard") {
            VStack(spacing: 6) {
                DialogKicker(text: "GAME \(number)" + (hardCore ? " · HARD CORE" : "") + (relaxed ? " · RELAXED" : ""))
                Text("You won!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(DialogColors.title)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Text("TIME")
                    .font(AppFont.mono(11, relativeTo: .caption2))
                    .tracking(1.5)
                    .foregroundStyle(DialogColors.label)
                Text(verbatim: GameHeader.clock(elapsed))
                    .font(AppFont.mono(wide ? 52 : 60, bold: true, relativeTo: .largeTitle))
                    .foregroundStyle(DialogColors.title)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(verbatim: moves == 1 ? "IN 1 MOVE" : "IN \(moves) MOVES")
                    .font(AppFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(DialogColors.body)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time \(GameHeader.spokenClock(elapsed))")
            .accessibilityValue("\(moves) moves")
            if let topTenRank {
                Text("New Top 10 · #\(topTenRank)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DialogColors.orangeText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(DialogColors.orangeText))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("topTenBadge")
            }
            HStack(spacing: 8) {
                figure("UNDOS", "\(undos)", spoken: undos == 1 ? "1 undo" : "\(undos) undos")
                figure("FREE CELLS", "\(freeCells)", spoken: "\(freeCells) free cells")
                figure("WINS", "\(wins)", spoken: wins == 1 ? "1 win" : "\(wins) wins")
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
        let new = Button("New Game", action: newGame)
            .buttonStyle(DialogButtonStyle(kind: .main, height: wide ? 44 : 54))
            .keyboardShortcut(.defaultAction)
        // In one row the main button gets whatever its neighbours leave, so its label is never cut.
        let choose = Button("Choose a game", action: chooseGame)
            .buttonStyle(DialogButtonStyle(kind: .outlined, height: wide ? 44 : 48, fills: !wide))
        let closeButton = Button("Close", action: close)
            .buttonStyle(DialogButtonStyle(kind: wide ? .outlined : .plain, height: 44, fills: !wide))
            .keyboardShortcut(.cancelAction)
        let topTen = Button("Top 10", action: showTopTen)
            .buttonStyle(DialogButtonStyle(kind: .outlined, height: wide ? 44 : 48, fills: !wide))
        Group {
            if wide {
                HStack(spacing: 8) { closeButton; topTen; choose; new }
            } else {
                VStack(spacing: 10) {
                    new
                    HStack(spacing: 10) { choose; topTen }
                    closeButton
                }
            }
        }
        .focusable(false)
    }
}

/// Choose a game (spec "Colours and dialogs", from the mockups): a game number from 1 to 1,000,000,
/// Microsoft's numbering. Play deals it, Random game deals a random one, Cancel changes nothing.
/// Opened mid-game it says the game will end, and Play is the confirmation — no second question.
struct ChooseGameCard: View {
    let inProgress: Bool
    let play: (Int) -> Void
    let random: () -> Void
    let cancel: () -> Void
    @State private var text = ""
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool

    /// The number typed, if it is a game number.
    nonisolated static func number(from text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = Int(digits), FreeCellEngine.numbers.contains(n) else { return nil }
        return n
    }

    var body: some View {
        let chosen = Self.number(from: text)
        DialogCard(identifier: "chooseGame") {
            DialogKicker(text: "NEW GAME")
            Text("Choose a game")
                .font(.title2.bold())
                .foregroundStyle(DialogColors.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text("Every number from 1 to 1,000,000 is the same deal on any FreeCell that uses Microsoft’s numbering, so you can trade games with friends.")
                .font(.callout)
                .foregroundStyle(DialogColors.body)
                .fixedSize(horizontal: false, vertical: true)
            if inProgress {
                Text("The game in progress will end.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DialogColors.orangeText)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("GAME NUMBER")
                    .font(AppFont.mono(11, relativeTo: .caption2))
                    .tracking(1.3)
                    .foregroundStyle(DialogColors.label)
                TextField("1 – 1000000", text: $text)
                    .textFieldStyle(.plain)
                    .font(AppFont.mono(28, bold: true, relativeTo: .title))
                    .foregroundStyle(DialogColors.title)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($fieldFocused)
                    .onSubmit { if let chosen { play(chosen) } }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0A0A0A)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DialogColors.orangeText, lineWidth: 1.5))
                    .accessibilityLabel("Game number")
                    .accessibilityIdentifier("gameNumber")
                Text("Game 11982 is the one game of the first 32,000 that can’t be won.")
                    .font(.footnote)
                    .foregroundStyle(DialogColors.label)
            }
            VStack(spacing: 10) {
                Button(chosen.map { "Play Game \($0)" } ?? "Play") { if let chosen { play(chosen) } }
                    .buttonStyle(DialogButtonStyle(kind: .main, height: 54))
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen == nil)
                    .opacity(chosen == nil ? 0.45 : 1)
                HStack(spacing: 10) {
                    Button("Random game", action: random)
                        .buttonStyle(DialogButtonStyle(kind: .outlined))
                    Button("Cancel", action: cancel)
                        .buttonStyle(DialogButtonStyle(kind: .outlined))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .focusable(false)
            .padding(.top, 4)
        }
        .onAppear {
            titleFocused = true
            fieldFocused = true
        }
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

/// Why a run didn't move (spec "Interaction"): a dark capsule over the bottom of the board, like the
/// dialogs, for a moment. VoiceOver hears it as an announcement.
struct NoticeBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DialogColors.title)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(DialogColors.card))
            .overlay(Capsule().strokeBorder(DialogColors.hairline))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("runLimitNotice")
    }
}
