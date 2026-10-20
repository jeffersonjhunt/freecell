import SolitaireEngine
import SwiftUI

@main
struct SolitaireApp: App {
    @State private var store: GameStore
    @State private var ui = AppUI()
    @State private var scores: ScoreBook
    @State private var gameCenter: GameCenter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.register()
        let store = SolitaireApp.makeStore()
        let scores = ScoreBook(local: AppSettings.defaults,
                               cloud: AppSettings.usesOutsideServices ? .default : nil)
        let gameCenter = GameCenter(enabled: AppSettings.usesOutsideServices)
        // Every win goes into the Top 10 and to its Game Center board (spec "Scores").
        store.onWin = { state in
            scores.record(state)
            gameCenter.submit(score: SolitaireEngine.score(state), drawCount: state.drawCount,
                              hardCore: state.isHardCore)
        }
        _store = State(initialValue: store)
        _scores = State(initialValue: scores)
        _gameCenter = State(initialValue: gameCenter)
    }

    /// The smallest Mac window: tall enough that, under the header and the bottom bar, cards stay
    /// about 50 pt wide or more.
    static let minimumWindow = CGSize(width: 600, height: 520)

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, ui: ui, scores: scores, gameCenter: gameCenter)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    store.isActive = phase == .active
                    if phase != .active { store.saveNow() }          // leaving the foreground
                }
                #if os(macOS)
                .frame(minWidth: Self.minimumWindow.width, minHeight: Self.minimumWindow.height)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 760)
        #endif
        .commands {
            GameCommands(store: store, ui: ui)
            HelpCommands(ui: ui)
            #if os(macOS)
            AboutCommands()
            #endif
        }

        #if os(macOS)
        Window("How to Play", id: HelpCommands.windowID) {
            HowToPlayView()
                .frame(minWidth: 420, idealWidth: 520, minHeight: 480, idealHeight: 640)
        }
        .defaultSize(width: 520, height: 640)

        Settings {
            SettingsView(store: store, ui: ui)
                .frame(width: 440, height: 600)
        }

        Window("Scores", id: ScoresWindow.id) {
            ScoresView(scores: scores, gameCenter: gameCenter, drawCount: store.state.drawCount)
                .frame(width: 420, height: 660)
        }
        .windowResizability(.contentSize)

        Window("About Solitaire", id: AboutCommands.windowID) {
            AboutView()
                .frame(width: 380)
        }
        .windowResizability(.contentSize)
        #endif
    }

    /// Resume the saved game if the player wants that and it is valid; otherwise deal fresh in the
    /// remembered draw mode. Undo always starts empty.
    private static func makeStore() -> GameStore {
        SaveLocation.resetForTests()
        let url = SaveLocation.url()
        let saver = url.map(GameSaver.init)
        let store: GameStore
        #if DEBUG
        if let scenario = UITestScenario.storeFromEnvironment() {
            scenario.saver = saver
            store = scenario
        } else {
            store = launchFromSave(url: url, saver: saver)
        }
        #else
        store = launchFromSave(url: url, saver: saver)
        #endif
        store.rememberDrawCount = { AppSettings.defaults.set($0, forKey: AppSettings.drawCountKey) }
        store.rememberHardCore = { AppSettings.defaults.set($0, forKey: AppSettings.hardCoreKey) }
        saveBeforeTheProcessMayEnd(store)
        return store
    }

    private static func launchFromSave(url: URL?, saver: GameSaver?) -> GameStore {
        let defaults = AppSettings.defaults
        let drawCount = defaults.object(forKey: AppSettings.drawCountKey) as? Int ?? 1
        let resume = defaults.object(forKey: AppSettings.resumeKey) as? Bool ?? true
        let hardCore = defaults.object(forKey: AppSettings.hardCoreKey) as? Bool ?? false
        let plan = LaunchPlan.decide(saved: url.flatMap(GameSaver.load(from:)), resumePreferred: resume,
                                     drawCount: drawCount, hardCore: hardCore)
        return GameStore.launch(plan, drawCount: drawCount, saver: saver)
    }

    /// Quitting on the Mac and backgrounding on iOS may end the process moments later, so wait for
    /// the save to reach disk there — not just start it. (A force quit gives the app no chance at
    /// all; then the last save stands: after every change and every fifth second.) Observers, not
    /// view modifiers, so this works with no window open.
    private static func saveBeforeTheProcessMayEnd(_ store: GameStore) {
        #if os(macOS)
        let name = NSApplication.willTerminateNotification
        #else
        let name = UIApplication.didEnterBackgroundNotification
        #endif
        _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { store.flushSaves() }
        }
    }
}

/// Settings live in UserDefaults (spec): the draw count of the last deal (default 1) and whether
/// to resume the game in progress at launch (default yes). Debug builds let UI tests use their own
/// suite, so a test choosing Draw 3 never changes the player's real preference.
enum AppSettings {
    static let drawCountKey = "drawCount"
    /// Whether the last deal was Hard Core (spec "Hard Core"); the next fresh deal follows it.
    static let hardCoreKey = "hardCore"
    static let resumeKey = "resumeOnLaunch"
    /// The card face and back (spec "Card styles"); an unknown stored value reads as the default.
    static let cardFaceKey = "cardFace"
    static let cardBackKey = "cardBack"
    /// Which side the draw pile sits on ("left" / "right"; spec "Top row"); unknown reads as left.
    static let drawPileSideKey = "drawPileSide"
    /// The win animation (spec "Win animations"); unknown reads as Cascade.
    static let winAnimationKey = "winAnimation"
    /// Whether a game in progress is asked about before a new deal replaces it (spec "New games
    /// and the draw mode"); unset or not a Bool reads as yes.
    static let askBeforeEndingGameKey = "askBeforeEndingGame"
    /// Settings ▸ Restart button (off by default; spec "Restart").
    static let restartButtonKey = "restartButton"

    static var askBeforeEndingGame: Bool { askBeforeEndingGame(in: defaults) }

    static func askBeforeEndingGame(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: askBeforeEndingGameKey) as? Bool ?? true
    }

    /// iCloud and Game Center are used by the app itself, never under tests (unit-test host or
    /// UI tests, which run with their own settings suite): tests must not touch the player's Top
    /// 10 or post scores (spec "Scores").
    static var usesOutsideServices: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] == nil && env["SOLITAIRE_DEFAULTS_SUITE"] == nil
    }

    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["SOLITAIRE_DEFAULTS_SUITE"],
           let custom = UserDefaults(suiteName: suite) {
            return custom
        }
        #endif
        return .standard
    }
}

/// Menus and keyboard shortcuts (spec: New Game ⌘N, Undo ⌘Z, Draw space, Auto-finish ⌘⏎, and
/// Toggle draw mode in a Game menu; the standard window and help groups stay). On the Mac, the
/// File menu also carries the new-game draw-count pair. The same commands give iPadOS its
/// hardware-keyboard shortcuts.
struct GameCommands: Commands {
    let store: GameStore
    let ui: AppUI
    @AppStorage(AppSettings.restartButtonKey, store: AppSettings.defaults) private var showsRestart = false

    var body: some Commands {
        // Every game command stands down while a card is up, so nothing changes behind it.
        CommandGroup(replacing: .newItem) {
            Group {
                Button("New Game") { ui.requestNewGame(store: store) }
                    .keyboardShortcut("n")
                Divider()
                Button("New Game: Draw 1") { ui.requestNewGame(drawCount: 1, store: store) }
                Button("New Game: Draw 3") { ui.requestNewGame(drawCount: 3, store: store) }
            }
            .disabled(ui.cardIsShowing)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { store.undo() }
                .keyboardShortcut("z")
                .disabled(!store.canUndo || ui.cardIsShowing)
        }
        CommandMenu("Game") {
            Group {
                Button("Draw") { store.tapStock() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Auto-finish") { store.autoFinish() }
                    .keyboardShortcut(.return)
                    .disabled(!store.canAutoFinish)
                if showsRestart {
                    Button("Restart Game") { ui.requestRestart(store: store) }
                        .keyboardShortcut("r")
                        .disabled(!store.canRestart)
                }
                Divider()
                // Switches as the draw chip does: a new deal in the other mode, asked first mid-game.
                Toggle("Draw Three", isOn: Binding(
                    get: { store.state.drawCount == 3 },
                    set: { ui.requestNewGame(drawCount: $0 ? 3 : 1, store: store) }))
            }
            .disabled(ui.cardIsShowing)
        }
    }
}


/// State for presentations that are not game state: the How to Play sheet on iPhone and iPad.
@Observable @MainActor
final class AppUI {
    var showingHelp = false
    /// Settings, About and Scores as sheets on iPhone and iPad (the Mac uses its own windows).
    var showingSettings = false
    var showingAbout = false
    var showingScores = false
    /// A new deal waiting for the player to confirm losing the game in progress.
    var pendingNewGame: NewGameRequest?
    /// Whether to ask before a new deal replaces a game in progress (the Settings switch; tests
    /// substitute their own).
    @ObservationIgnored var asksBeforeEndingGame: () -> Bool = { AppSettings.askBeforeEndingGame }
    /// The win card is on screen (set by ContentView, which decides when it shows).
    var showingWinCard = false
    /// The More card is open.
    var showingMore = false
    /// A dark card (a question or the win card) is up: it is modal, so the game's menu commands
    /// and shortcuts stand down until it closes (spec "Colours and dialogs").
    var cardIsShowing: Bool { pendingNewGame != nil || showingWinCard || showingMore }
}

/// Help ▸ Solitaire Help (⌘?): the How to Play window on the Mac, the help sheet on iPad with a
/// keyboard. Replaces the standard "help isn't available" item.
struct HelpCommands: Commands {
    static let windowID = "how-to-play"
    let ui: AppUI
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Solitaire Help") {
                #if os(macOS)
                openWindow(id: Self.windowID)
                #else
                ui.showingHelp = true
                #endif
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

#if os(macOS)
/// Solitaire ▸ About Solitaire opens the app's own About window, replacing the standard panel.
struct AboutCommands: Commands {
    static let windowID = "about"
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Solitaire") { openWindow(id: Self.windowID) }
        }
    }
}
#endif

/// The Mac's Scores window.
enum ScoresWindow {
    static let id = "scores"
}
