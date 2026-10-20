import SolitaireEngine
import SwiftUI

/// Settings (spec "Settings, About and the More menu"): resuming at launch, the draw pile's side,
/// and the card face and back, with a live preview. (The draw mode is the draw chip's, not a setting.) A sheet on iPhone and iPad, the Settings window (⌘,) on the Mac.
/// Every change is saved and applied at once, the game in progress included.
struct SettingsView: View {
    let store: GameStore
    let ui: AppUI
    @AppStorage(AppSettings.resumeKey, store: AppSettings.defaults) private var resumeOnLaunch = true
    @AppStorage(AppSettings.cardFaceKey, store: AppSettings.defaults) private var face = CardFaceStyle.classic
    @AppStorage(AppSettings.cardBackKey, store: AppSettings.defaults) private var back = CardBackStyle.classicBlue
    @AppStorage(AppSettings.drawPileSideKey, store: AppSettings.defaults) private var drawPileSide = DrawPileSide.left
    @AppStorage(AppSettings.winAnimationKey, store: AppSettings.defaults) private var winAnimation = WinAnimation.cascade
    @AppStorage(AppSettings.askBeforeEndingGameKey, store: AppSettings.defaults) private var askBeforeEndingGame = true
    @AppStorage(AppSettings.restartButtonKey, store: AppSettings.defaults) private var restartButton = false

    private static let previewAce = Card(suit: .spades, rank: 1, isFaceUp: true)
    private static let previewKing = Card(suit: .hearts, rank: 13, isFaceUp: true)
    private static let sampleFace = Card(suit: .hearts, rank: 1, isFaceUp: true)
    private static let sampleBack = Card(suit: .clubs, rank: 2, isFaceUp: false)

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    CardView(card: Self.sampleBack, width: 66)
                    CardView(card: Self.previewAce, width: 66)
                    CardView(card: Self.previewKing, width: 66)
                }
                .environment(\.cardStyle, CardStyle(face: face, back: back))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background { TableBackground().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                .listRowInsets(EdgeInsets())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview: \(face.title) face, \(back.title) back")
            }
            Section("Game") {
                // Named explicitly: in the Mac's grouped form the label is a separate text, and the
                // switch alone would reach VoiceOver unnamed.
                Toggle("Resume game at launch", isOn: $resumeOnLaunch)
                    .accessibilityLabel("Resume game at launch")
                    .tint(TableColors.accent)
                // Shows the current game's mode; changing it deals a new game (spec "Hard Core").
                // Settings closes first, so the question (if any) shows over the game.
                Toggle(isOn: Binding(get: { store.state.isHardCore }, set: { on in
                    closeSettings()
                    ui.requestNewGame(hardCore: on, store: store)
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hard Core")
                        Text("Draw 1: one pass through the deck. Draw 3: three. Changing it starts a new game.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Hard Core")
                .accessibilityHint("Limits passes through the deck. Changing it starts a new game")
                .tint(TableColors.accent)
                Toggle("Draw pile on the right", isOn: Binding(
                    get: { drawPileSide == .right },
                    set: { drawPileSide = $0 ? .right : .left }))
                    .accessibilityLabel("Draw pile on the right")
                    .tint(TableColors.accent)
                Toggle("Ask before ending a game", isOn: $askBeforeEndingGame)
                    .accessibilityLabel("Ask before ending a game")
                    .accessibilityHint("Asks before New Game or the draw switch replaces a game in progress")
                    .tint(TableColors.accent)
                Toggle("Restart button", isOn: $restartButton)
                    .accessibilityLabel("Restart button")
                    .accessibilityHint("Shows a button that plays the same deal again from the start. A restarted game scores 0")
                    .tint(TableColors.accent)
            }
            Section {
                Picker("Animation", selection: $winAnimation) {
                    ForEach(WinAnimation.allCases) { Text($0.title).tag($0) }
                }
                .tint(TableColors.accent)
            } header: {
                Text("Win animation")
            } footer: {
                Text("Random picks one of the four for each win. With Reduce Motion on, none plays.")
            }
            Section("Card face") {
                StyleChooser(selection: $face) { style in
                    CardView(card: Self.sampleFace, width: 44)
                        .environment(\.cardStyle, CardStyle(face: style, back: back))
                }
            }
            Section {
                StyleChooser(selection: $back) { style in
                    CardView(card: Self.sampleBack, width: 44)
                        .environment(\.cardStyle, CardStyle(face: face, back: style))
                }
            } header: {
                Text("Card back")
            } footer: {
                Text("Faces and backs change every card at once, including the game in progress.")
            }
        }
        .formStyle(.grouped)
    }
}

extension SettingsView {
    /// Closes Settings: the sheet on iPhone and iPad, the window on the Mac.
    func closeSettings() {
        #if os(macOS)
        NSApp.keyWindow?.close()
        #else
        ui.showingSettings = false
        #endif
    }
}

/// A row of tappable previews, the current one ringed in burnt orange.
private struct StyleChooser<Style: Hashable & Identifiable & CaseIterable, Preview: View>: View
where Style.AllCases: RandomAccessCollection, Style: TitledStyle {
    @Binding var selection: Style
    @ViewBuilder let preview: (Style) -> Preview

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Style.allCases) { style in
                let selected = style == selection
                Button { selection = style } label: {
                    VStack(spacing: 6) {
                        preview(style)
                        Text(style.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? TableColors.accent : .clear, lineWidth: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

protocol TitledStyle { var title: String { get } }
extension CardFaceStyle: TitledStyle {}
extension CardBackStyle: TitledStyle {}

/// About (spec "Settings, About and the More menu"): the app, its version, its maker, links (which
/// open in the browser — the app's own code has no network code; iCloud and Game Center are the
/// system's), and acknowledgements.
struct AboutView: View {
    @State private var showingLicence = false

    static let website = URL(string: "https://oneoffendeavors.com")!
    static let privacy = URL(string: "https://oneoffendeavors.com/solitaire/privacy/")!
    static let support = URL(string: "https://oneoffendeavors.com/solitaire/support/")!

    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .accessibilityHidden(true)
                    Text("Solitaire")
                        .font(.title.bold())
                        .padding(.top, 8)
                    Text("Version \(Self.version)")
                        .font(AppFont.mono(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                    Text("Klondike, made by One Off Endeavors. No ads, no tracking, nothing to sign up for. Your Top 10 syncs through your own iCloud, and your wins go to Game Center when you're signed in.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                ExternalLink(title: "One Off Endeavors", url: Self.website)
                ExternalLink(title: "Privacy policy", url: Self.privacy)
                ExternalLink(title: "Support and feedback", url: Self.support)
            }
            Section("Acknowledgements") {
                Button { showingLicence = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Space Mono")
                                .foregroundStyle(.primary)
                            Text("© 2016 The Space Mono Project Authors · SIL Open Font License 1.1")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Section {
                Text("© 2026 One Off Endeavors")
                    .font(AppFont.mono(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingLicence) { LicenceView { showingLicence = false } }
    }
}

/// A row that opens a web page in the browser: text in the normal colour (the app's tint is too
/// pale for text on white), with an arrow saying it leaves the app.
private struct ExternalLink: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens in your browser")
    }
}

/// The SIL Open Font License, as shipped with Space Mono (Resources/Fonts/OFL.txt).
struct LicenceView: View {
    let done: () -> Void

    static var text: String {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(Self.text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Space Mono licence")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}
