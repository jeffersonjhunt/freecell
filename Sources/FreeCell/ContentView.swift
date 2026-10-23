import SwiftUI
import FreeCellEngine

/// The whole window, the same on every platform: the green table, the header with time, moves and
/// the game chip, the board, the bar along the bottom, and on a win its animation plus the win
/// card with the time and moves.
struct ContentView: View {
    let store: GameStore
    let ui: AppUI
    let scores: ScoreBook
    let gameCenter: GameCenter
    /// The deal whose win card was closed (by the store's deal identity: a restarted game is a new
    /// deal of the same number, and its win shows the card again).
    @State private var dismissedWinDeal: UUID?
    /// The deal whose win animation has finished; the win card waits for it, so it plays uncovered.
    @State private var animationFinishedDeal: UUID?
    /// Why the last run didn't move, shown for a moment over the bottom of the board.
    @State private var shownNotice: GameStore.Notice?
    /// The width the eight columns actually use, so the header lines up with the cards.
    @State private var boardWidth: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage(AppSettings.cardFaceKey, store: AppSettings.defaults) private var cardFace = CardFaceStyle.classic
    @AppStorage(AppSettings.cardBackKey, store: AppSettings.defaults) private var cardBack = CardBackStyle.classicBlue
    @AppStorage(AppSettings.winAnimationKey, store: AppSettings.defaults) private var winAnimation = WinAnimation.cascade
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// A phone held sideways: the header folds into the bar, so the cards keep its height.
    private var shortScreen: Bool { verticalSizeClass == .compact }
    #else
    private let shortScreen = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !shortScreen { GameHeader(store: store, ui: ui, width: boardWidth) }
            BoardView(store: store) { animationFinishedDeal = store.dealID }   // draws the win animation itself
                .overlay(alignment: .bottom) {
                    if let notice = shownNotice {
                        NoticeBanner(text: notice.text)
                            .padding(.bottom, 14)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                    }
                }
                .onChange(of: store.notice) { _, notice in
                    guard let notice else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { shownNotice = notice }
                    AccessibilityNotification.Announcement(notice.text).post()
                    Task {
                        try? await Task.sleep(for: .seconds(2.5))
                        if shownNotice == notice {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { shownNotice = nil }
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { [isTouch = BoardView.isTouch] proxy in
                    BoardMetrics(size: proxy.size, isTouch: isTouch).usedWidth
                } action: { boardWidth = $0 }
            ActionBar(store: store, ui: ui, withStats: shortScreen)
        }
        .background(TableBackground().ignoresSafeArea())
        .environment(\.cardStyle, CardStyle(face: cardFace, back: cardBack))
        .environment(\.winAnimation, playedAnimation)
        #if os(macOS)
        .background(QuitWhenClosed())
        #endif
        #if os(iOS)
        // Haptics, iOS and iPadOS only: light on a move, success on a win.
        .sensoryFeedback(trigger: store.feedback) { _, event in
            switch event?.kind {
            case .move: .impact(weight: .light)
            case .win: .success
            case nil: nil
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: Binding(get: { ui.showingHelp }, set: { ui.showingHelp = $0 })) {
            NavigationStack {
                HowToPlayView { ui.showingHelp = false }
            }
        }
        .sheet(isPresented: Binding(get: { ui.showingSettings }, set: { ui.showingSettings = $0 })) {
            NavigationStack {
                SettingsView(store: store, ui: ui)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { ui.showingSettings = false } }
                    }
            }
        }
        .sheet(isPresented: Binding(get: { ui.showingScores }, set: { ui.showingScores = $0 })) {
            ScoresView(scores: scores, gameCenter: gameCenter) {
                ui.showingScores = false
            }
            .presentationBackground(DialogColors.card)
        }
        .sheet(isPresented: Binding(get: { ui.showingAbout }, set: { ui.showingAbout = $0 })) {
            NavigationStack {
                AboutView()
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { ui.showingAbout = false } }
                    }
            }
        }
        #endif
        // New Game, Hard Core, Restart and the menus ask here before losing a game in progress;
        // Choose a game opens here; the win card follows the win animation. All are dark cards
        // over the dimmed table.
        .overlay {
            if ui.choosingGame {
                DialogScrim(bottom: !wideDialogs, maxWidth: 480, outside: { ui.choosingGame = false }) {
                    ChooseGameCard(inProgress: store.isInProgress,
                                   play: { number in
                                       ui.choosingGame = false
                                       ui.requestNewGame(number: number, confirmed: true, store: store)
                                   },
                                   random: {
                                       ui.choosingGame = false
                                       ui.requestNewGame(confirmed: true, store: store)
                                   },
                                   cancel: { ui.choosingGame = false })
                }
                .transition(.opacity)
            } else if let request = ui.pendingNewGame {
                DialogScrim(outside: { ui.pendingNewGame = nil }) {
                    QuestionCard(request: request, cancel: { ui.pendingNewGame = nil }) {
                        ui.confirmPending(store: store)
                    }
                }
                .transition(.opacity)
            } else if winSheetShown.wrappedValue {
                DialogScrim(bottom: !wideDialogs, maxWidth: 480) {
                    WinCard(number: store.state.number, hardCore: store.state.isHardCore, relaxed: store.state.isRelaxed,
                            moves: store.state.moveCount, elapsed: store.state.elapsed,
                            undos: store.state.undos, freeCells: store.state.cells.count,
                            wins: scores.wins.total, topTenRank: scores.rank(ofWin: store.state),
                            wide: wideDialogs, showTopTen: showScores,
                            newGame: { store.newGame() },
                            chooseGame: { ui.choosingGame = true },
                            close: { dismissedWinDeal = store.dealID })
                }
                .transition(.opacity)
            } else if ui.showingMore {
                DialogScrim(bottom: !wideDialogs, maxWidth: 420, outside: { ui.showingMore = false }) {
                    MoreCard(ui: ui, showScores: showScores)
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: ui.pendingNewGame)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: ui.choosingGame)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: ui.showingMore)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: winSheetShown.wrappedValue)
        .onChange(of: winSheetShown.wrappedValue, initial: true) { _, shown in ui.showingWinCard = shown }
        .task { gameCenter.signIn() }                                  // Game Center's own prompt, once
    }

    /// The win animation this game plays: the chosen one, Random settled for this deal — or none
    /// (None, or Reduce Motion), in which case the win card comes at once.
    private var playedAnimation: WinAnimation? {
        reduceMotion ? nil : winAnimation.resolved(seed: UInt64(truncatingIfNeeded: store.dealID.hashValue))
    }

    /// Scores: a sheet on iPhone and iPad, its window on the Mac.
    private func showScores() {
        #if os(macOS)
        openWindow(id: ScoresWindow.id)
        #else
        ui.showingScores = true
        #endif
    }

    /// Cards centred with their buttons in a row (iPad, the Mac, a phone held sideways), rather
    /// than anchored to the bottom with stacked buttons (a phone held upright).
    private var wideDialogs: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular || verticalSizeClass == .compact
        #else
        true
        #endif
    }

    private var winSheetShown: Binding<Bool> {
        Binding(
            get: {
                Self.showsWinSheet(isWon: store.state.isWon, dismissed: dismissedWinDeal == store.dealID,
                                   cascadeFinished: animationFinishedDeal == store.dealID,
                                   reduceMotion: playedAnimation == nil, voiceOver: voiceOver)
            },
            set: { shown in if !shown { dismissedWinDeal = store.dealID } }
        )
    }

    /// The win sheet: once per won game, after its cascade so the cascade plays uncovered — but at
    /// once under Reduce Motion (there is no cascade) or VoiceOver (the cascade is silent and can't
    /// be skipped by touch; the sheet is what VoiceOver reads). Closing it leaves the finished board
    /// and the trail (New Game is in the bar along the bottom).
    nonisolated static func showsWinSheet(isWon: Bool, dismissed: Bool, cascadeFinished: Bool,
                                          reduceMotion: Bool, voiceOver: Bool) -> Bool {
        isWon && !dismissed && (cascadeFinished || reduceMotion || voiceOver)
    }
}

/// A dark green gradient; card faces stay readable on it in light and dark mode.
struct TableBackground: View {
    var body: some View {
        LinearGradient(colors: [Color("TableTop"), Color("TableBottom")], startPoint: .top, endPoint: .bottom)
    }
}

#Preview {
    ContentView(store: GameStore(), ui: AppUI(), scores: ScoreBook(local: .standard, cloud: nil), gameCenter: GameCenter(enabled: false))
}

#if os(macOS)
/// The game window is the app (spec): closing it quits FreeCell — saving as any quit does — so
/// it never runs without a game on screen. Other windows (How to Play, About, Settings) close
/// with it. Watches this view's own window, so only the game window's closing counts.
private struct QuitWhenClosed: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowWatcher() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowWatcher: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }
}
#endif
