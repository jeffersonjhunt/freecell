import XCTest

/// End-to-end checks in the running app (XCUITest drives real taps and drags).
@MainActor
final class SolitaireUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The UI tests' own save file and settings suite: no UI test reads or overwrites the player's
    /// real game or preferences (on the Mac they share the real app's container). One fixed name,
    /// reset at the start of each test, so runs never leave files piling up.
    private let isolation = "uitest"

    /// Launches the app with a Debug scenario or seed, passed in the environment (see
    /// UITestScenario). `reset: false` keeps the previous launch's save — for relaunch tests.
    /// `arguments` are extra launch arguments, e.g. `["-cardFace", "night"]` to put a value in the
    /// arguments domain, which every UserDefaults read sees first.
    private func launch(scenario: String? = nil, seed: UInt64? = nil, reset: Bool = true,
                        arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOLITAIRE_SAVE_FILE"] = isolation
        app.launchEnvironment["SOLITAIRE_DEFAULTS_SUITE"] = isolation
        if reset { app.launchEnvironment["SOLITAIRE_RESET"] = "1" }
        // Ignore saved window state, as Xcode does for the unit-test host. A run that quit with no
        // window open saves "no windows", and XCUITest's launch (unlike Finder or the Dock) does not
        // send the "open application" event that would open one anyway — the app came up windowless.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + arguments
        if let scenario { app.launchEnvironment["SOLITAIRE_SCENARIO"] = scenario }
        if let seed { app.launchEnvironment["SOLITAIRE_SEED"] = String(seed) }
        app.launch()
        return app
    }

    /// Acceptance 5: a game played to a win shows the win sheet with the move count and time — after
    /// the cascade, which it must not cover; a click on the cascade skips straight to it.
    func testAutoFinishWinsAndShowsTheWinSheet() {
        let app = launch(scenario: "almostWon")
        let autoFinish = app.buttons["Auto-finish"]
        XCTAssertTrue(autoFinish.waitForExistence(timeout: 5), "Auto-finish should be offered")
        autoFinish.press()
        XCTAssertTrue(app.staticTexts["12 moves"].waitForExistence(timeout: 5), "twelve auto-finish moves")
        XCTAssertFalse(app.staticTexts["You won!"].waitForExistence(timeout: 3), "the cascade plays uncovered")
        // Skip the cascade with a click on the board. (A point, not the window element: on the Mac
        // XCUITest's click on a window never reaches its content.)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 5))
        // The win card: both modes straight away (the game is over, nothing to confirm), and Close
        // leaves the finished board.
        let card = app.descendants(matching: .any)["winCard"]
        XCTAssertTrue(card.exists, "the win card")
        XCTAssertTrue(card.buttons["New Game · Draw 1"].exists && card.buttons["Draw 3 instead"].exists)
        XCTAssertTrue(card.descendants(matching: .any)["1 pass"].exists, "passes on the win card")
        XCTAssertTrue(card.descendants(matching: .any)["0 undos"].exists, "undos on the win card")
        XCTAssertTrue(card.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Score '")).firstMatch.exists,
                      "the score on the win card")
        // The first win of a fresh Top 10 is #1 (spec "Scores"); Top 10 opens Scores on that mode.
        XCTAssertTrue(card.descendants(matching: .any)["topTenBadge"].exists, "the New Top 10 badge")
        // Text is a label on iPhone and a value on the Mac: read whichever is set.
        let badge = card.descendants(matching: .any)["topTenBadge"]
        XCTAssertEqual(badge.label.isEmpty ? "\(badge.value ?? "")" : badge.label, "New Top 10 · #1 in Draw 1")
        card.buttons["Top 10"].press()
        let scores = app.descendants(matching: .any)["scores"]
        XCTAssertTrue(scores.waitForExistence(timeout: 5), "Scores")
        XCTAssertTrue(scores.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '1. '")).firstMatch.exists,
                      "the win in the Top 10")
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)                         // the Scores window
        #else
        scores.buttons["Done"].press()
        #endif
        XCTAssertTrue(scores.waitForNonExistence(timeout: 5))
        card.buttons["Close"].press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForNonExistence(timeout: 5), "Close dismisses it")
    }

    /// Each win animation (spec "Win animations") plays to its end by itself and then the win card
    /// appears; with None the win card comes at once.
    func testEveryWinAnimationEndsInTheWinCard() {
        for animation in ["rainfall", "decay", "shuffle"] {
            let app = launch(scenario: "almostWon", arguments: ["-winAnimation", animation])
            XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
            app.buttons["Auto-finish"].press()
            XCTAssertTrue(app.staticTexts["12 moves"].waitForExistence(timeout: 5), animation)
            XCTAssertFalse(app.staticTexts["You won!"].waitForExistence(timeout: 1), "\(animation) plays uncovered")
            XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 30), "\(animation) ends in the win card")
            app.terminate()
        }
        let app = launch(scenario: "almostWon", arguments: ["-winAnimation", "none"])
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        app.buttons["Auto-finish"].press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 6), "None: the win card at once")
    }

    /// Left alone, the cascade runs to its end and then the win sheet appears.
    func testWinSheetFollowsTheCascade() {
        let app = launch(scenario: "almostWon")
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        app.buttons["Auto-finish"].press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 60), "the cascade should end")
    }

    /// Acceptance 6: a king alone at the bottom of a column reaches an empty column by drag, but a
    /// tap offers nothing (it would only shuffle columns).
    func testKingToAnEmptyColumnByDragNotByTap() {
        let app = launch(scenario: "kingAlone")
        let king = app.buttons["King of Hearts, column 1"].exists
            ? app.buttons["King of Hearts, column 1"] : app.staticTexts["King of Hearts, column 1"]
        XCTAssertTrue(king.waitForExistence(timeout: 5))
        let emptyColumn = app.descendants(matching: .any)["Column 2, empty"]
        XCTAssertTrue(emptyColumn.exists)

        king.press()
        // Give a (wrong) move time to happen before asserting that none did.
        XCTAssertFalse(app.descendants(matching: .any)["King of Hearts, column 2"].waitForExistence(timeout: 1),
                       "a tap must not move it")
        XCTAssertTrue(app.descendants(matching: .any)["King of Hearts, column 1"].exists)
        XCTAssertTrue(emptyColumn.exists, "column 2 is still empty")

        king.drag(to: emptyColumn)
        XCTAssertTrue(app.descendants(matching: .any)["King of Hearts, column 2"].waitForExistence(timeout: 5),
                      "the drag should have moved it")
    }

    /// The profiling position works in the app: the whole King→Ace run drags to the empty column.
    func testKingToAceRunDragsWhole() {
        let app = launch(scenario: "kingToAce")
        let king = app.descendants(matching: .any)["King of Spades, column 1"]
        XCTAssertTrue(king.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Ace of Spades, column 1"].exists)
        king.drag(to: app.descendants(matching: .any)["Column 2, empty"], grabAt: 0.08)   // its visible strip
        XCTAssertTrue(app.descendants(matching: .any)["King of Spades, column 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Ace of Spades, column 2"].exists, "the run moved whole")
    }

    /// Repeated clicks on the stock each draw in the running app. (XCUITest spaces clicks ~0.55 s
    /// apart — just over the macOS double-click interval — so the "however fast" half of the rule
    /// is covered by the `Routing` unit tests, not here.)
    func testFastClicksOnTheStockEachDraw() {
        let app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        app.descendants(matching: .any)["Stock, 23 cards"].press()
        app.descendants(matching: .any)["Stock, 22 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 21 cards"].waitForExistence(timeout: 5))
    }

    #if os(macOS)
    /// The Game and Edit menus follow the game: Undo enables after a move, Auto-finish only when it
    /// is available.
    func testMenuItemsFollowTheGame() {
        let app = launch(scenario: "almostWon")
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        func menuItem(_ menu: String, _ item: String) -> XCUIElement {
            app.menuBars.menuBarItems[menu].click()
            return app.menuBars.menuItems[item]
        }
        XCTAssertTrue(menuItem("Game", "Auto-finish").isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(menuItem("Edit", "Undo").isEnabled, "nothing to undo yet")
        app.typeKey(.escape, modifierFlags: [])
        app.descendants(matching: .any)["Jack of Spades, column 1"].press()   // one move to a foundation
        XCTAssertTrue(menuItem("Edit", "Undo").isEnabled, "a move can be undone")
        app.typeKey(.escape, modifierFlags: [])
    }
    #endif

    /// Acceptance 7: force-quitting mid-game and relaunching restores the same board, move count and
    /// elapsed time.
    func testForceQuitAndRelaunchRestoresTheGame() throws {
        var app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        app.descendants(matching: .any)["Stock, 23 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 22 cards"].waitForExistence(timeout: 5))
        let waste = wasteTop(app)
        sleep(6)                                          // the clock passes a five-second save
        let before = try seconds(app)
        XCTAssertGreaterThanOrEqual(before, 5)

        app.terminate()                                   // force quit: no chance to save
        app = launch(reset: false)                        // same save file, no seed: resume
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 22 cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, equalTo: "2 moves").exists, "move count restored")
        XCTAssertEqual(wasteTop(app), waste, "same board")
        // Restored to the last save — at most five seconds back (decision). The clock runs again
        // once relaunched, so allow for the relaunch itself (slower on iOS) above.
        let after = try seconds(app)
        XCTAssertTrue((before - 5)...(before + Self.relaunchSlack) ~= after,
                      "elapsed \(after) s after quitting at \(before) s")
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "a resumed game starts with undo empty")
    }

    /// Quitting normally (⌘Q on the Mac; iOS sending the app to the background) saves on the spot,
    /// so the elapsed time comes back exactly — not rounded down to the last five-second save.
    func testQuittingNormallyKeepsTheExactTime() throws {
        var app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        sleep(8)                                          // between five-second saves (7-8 s)
        let before = try seconds(app)
        XCTAssertTrue(before % 5 != 0, "not on a save boundary (\(before) s), or the test proves nothing")
        #if os(macOS)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        #else
        XCUIDevice.shared.press(.home)                    // background: the app saves on the spot
        sleep(2)
        app.terminate()
        #endif
        app = launch(reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        // Never less than when it quit (a rounded-down five-second save would be), plus the
        // seconds the clock runs until the quit and again after the relaunch.
        let after = try seconds(app)
        XCTAssertTrue(before...(before + Self.relaunchSlack) ~= after,
                      "elapsed \(after) s after quitting at \(before) s")
    }

    /// Seconds the clock keeps running around a quit and relaunch (quit ~1 s, iOS relaunch ~3 s).
    private static let relaunchSlack = 6

    /// New Game deals at once on a fresh deal; mid-game it asks, and Cancel keeps the game.
    /// Random deals (no seed): a seeded launch deals that seed every time, so a new deal would
    /// look identical.
    func testNewGameAsksOnlyWhenAGameWouldBeLost() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        let firstDeal = dealSignature(app)
        XCTAssertEqual(firstDeal.count, 7)
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNil(confirmation(app, timeout: 2), "nothing to lose on a fresh deal: no question")
        XCTAssertNotEqual(dealSignature(app), firstDeal, "dealt at once")
        app.descendants(matching: .any)["Stock, 24 cards"].press()                  // a move
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        app.buttons["New Game"].firstMatch.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, New Game asks first")
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 3), "Cancel keeps the game")
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNotNil(confirmation(app))
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press()
        XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3),
                      "a tap on the dimmed table cancels")
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].exists, "and keeps the game")
        #if os(macOS)
        // The question is modal: Space (Draw) and ⌘Z (Undo) don't reach the game behind it. Each
        // is tried on its own (together they would cancel out), and checked once the card is gone
        // (the board is hidden from accessibility while it is up).
        for (key, modifiers, name) in [(" ", XCUIElement.KeyModifierFlags(), "Space"), ("z", .command, "⌘Z")] {
            app.buttons["New Game"].firstMatch.press()
            XCTAssertNotNil(confirmation(app))
            app.typeKey(key, modifierFlags: modifiers)
            sleep(1)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3), "Esc cancels")
            XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].exists, "\(name) didn't reach the game")
        }
        #endif
        app.buttons["New Game"].firstMatch.press()
        confirmation(app)?.buttons["New Game"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5), "confirmed: a new deal")
    }

    /// Settings ▸ Ask before ending a game, turned off: New Game mid-game deals at once, and the
    /// choice survives a relaunch.
    func testAskingCanBeTurnedOff() {
        var app = launch()
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Ask before ending a game")
        XCTAssertNotNil(toggle)
        // A switch's value is "1" on iPhone and the number 1 on the Mac: compare as text.
        XCTAssertEqual(toggle.map { "\($0.value ?? "")" }, "1", "on by default")
        toggle?.press()
        closeSettings(app)
        app.descendants(matching: .any)["Stock, 24 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNil(confirmation(app, timeout: 2), "no question")
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5), "dealt at once")
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["Stock, 24 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["drawChip"].press()
        XCTAssertNil(confirmation(app, timeout: 2), "still off after a relaunch; the chip doesn't ask either")
        XCTAssertEqual(app.descendants(matching: .any)["drawChip"].label, "Draw three")
    }

    /// Restart (spec "Restart"): no button until Settings ▸ Restart button is on; then it is off on
    /// a fresh deal, asks mid-game, and deals the same cards again; the setting survives a relaunch.
    func testRestart() {
        var app = launch(seed: 7)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        let deal = dealSignature(app)
        XCTAssertFalse(app.buttons["Restart"].exists, "off by default")
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Restart button")
        XCTAssertEqual(toggle.map { "\($0.value ?? "")" }, "0", "off by default")
        toggle?.press()
        closeSettings(app)
        let restart = app.buttons["Restart"].firstMatch
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "in the bar")
        XCTAssertFalse(restart.isEnabled, "a fresh deal is already the start")
        stock.press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        restart.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, it asks")
        XCTAssertTrue(ask?.staticTexts["Restart this game?"].exists ?? false)
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 3), "Cancel keeps the game")
        restart.press()
        confirmation(app)?.buttons["Restart"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5), "from the start")
        XCTAssertEqual(dealSignature(app), deal, "the same deal")
        XCTAssertTrue(app.descendants(matching: .any)["Score 0"].exists)
        #if os(macOS)
        app.descendants(matching: .any)["Stock, 24 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        app.typeKey("r", modifierFlags: .command)
        XCTAssertNotNil(confirmation(app), "⌘R restarts too")
        app.typeKey(.escape, modifierFlags: [])
        #endif
        app.terminate()
        app = launch(seed: 7, reset: false)
        XCTAssertTrue(app.buttons["Restart"].firstMatch.waitForExistence(timeout: 5), "still on after a relaunch")
    }

    /// Hard Core (spec "Hard Core"): the Settings switch deals a Hard Core game at once on a fresh
    /// deal; Draw 1 then gets one pass — the empty stock shows ✕ and doesn't redeal; turning it off
    /// mid-game asks, and Cancel keeps the Hard Core game.
    func testHardCore() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Hard Core")
        XCTAssertNotNil(toggle)
        toggle?.press()
        XCTAssertTrue(app.descendants(matching: .any)["moreCard"].waitForNonExistence(timeout: 2))
        let chip = app.descendants(matching: .any)["drawChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertNil(confirmation(app, timeout: 1), "a fresh deal: no question")
        XCTAssertEqual(chip.label, "Draw one, Hard Core", "Settings closed and a Hard Core game was dealt")
        for _ in 0..<24 {
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Stock'")).firstMatch.press()
        }
        let out = app.descendants(matching: .any)["Stock, empty. No passes left"]
        XCTAssertTrue(out.waitForExistence(timeout: 5), "one pass in Draw 1: no redeal")
        out.press()
        XCTAssertTrue(out.exists, "tapping it does nothing")
        more(app, "Settings")
        settingsSwitch(app, "Hard Core")?.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, turning it off asks")
        XCTAssertTrue(ask?.staticTexts["Turn off Hard Core?"].exists ?? false)
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["drawChip"].label, "Draw one, Hard Core", "Cancel keeps it")
    }

    /// Scores from More, before any win: an empty Top 10 says so.
    func testScoresStartEmpty() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "Scores")
        let scores = app.descendants(matching: .any)["scores"]
        XCTAssertTrue(scores.waitForExistence(timeout: 5))
        XCTAssertTrue(scores.staticTexts["No wins yet in Draw 1."].exists)
        // Separate text on iPhone; part of the board row's label on the Mac.
        XCTAssertTrue(scores.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Not signed in'")).firstMatch.exists,
                      "Game Center is off under tests")
    }

    /// The header leads with the score (spec "Scoring"): 0 on a fresh deal.
    func testTheHeaderShowsTheScore() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Score 0"].waitForExistence(timeout: 5))
    }

    /// The draw chip switches mode by dealing: at once on a fresh deal, asked first mid-game; the
    /// mode survives a relaunch. Random deals (no seed): a seeded launch always builds a fresh
    /// Draw 1 game and ignores the save, so it could never show the mode being remembered.
    func testDrawChipSwitchesTheDrawMode() {
        var app = launch()
        let chip = app.descendants(matching: .any)["drawChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Draw one")
        chip.press()
        XCTAssertNil(confirmation(app, timeout: 2), "a fresh deal switches without asking")
        XCTAssertEqual(chip.label, "Draw three")
        app.descendants(matching: .any)["Stock, 24 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 21 cards"].waitForExistence(timeout: 5), "a draw-3 deal")
        chip.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, the chip asks first")
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 21 cards"].waitForExistence(timeout: 3), "Cancel keeps the game")
        XCTAssertEqual(chip.label, "Draw three")
        chip.press()
        confirmation(app)?.buttons["Start New Game"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Draw one")
        chip.press()                                                                // fresh: Draw 3 again
        XCTAssertEqual(app.descendants(matching: .any)["drawChip"].label, "Draw three")
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["drawChip"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["drawChip"].label, "Draw three", "remembered")
        #if os(macOS)
        // The Game menu's Draw Three switches as the chip does.
        app.menuBars.menuBarItems["Game"].click()
        app.menuBars.menuItems["Draw Three"].click()
        XCTAssertEqual(app.descendants(matching: .any)["drawChip"].label, "Draw one")
        #endif
    }

    #if os(macOS)
    /// Closing the game window quits the app — even with another of its windows open — so ⌘N can
    /// never act on a game that isn't on screen.
    func testClosingTheGameWindowQuits() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "About")
        XCTAssertTrue(app.windows["About Solitaire"].waitForExistence(timeout: 5))
        let game = app.windows.matching(NSPredicate(format: "title == 'Solitaire'")).firstMatch
        XCTAssertTrue(game.exists, "the game window")
        game.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "closing the game window quits")
    }
    #endif

    #if os(iOS)
    /// The cards follow Larger Text, and at the largest accessibility size the card still fits on
    /// screen (it scrolls rather than running off).
    func testCardsFollowLargerText() {
        func titleHeight(_ arguments: [String]) -> (CGFloat, Bool) {
            let app = launch(seed: 4, arguments: arguments)
            let stock = app.descendants(matching: .any)["Stock, 24 cards"]
            XCTAssertTrue(stock.waitForExistence(timeout: 5))
            stock.press()
            app.buttons["New Game"].firstMatch.press()
            guard let card = confirmation(app) else { XCTFail("no question"); return (0, false) }
            let title = card.staticTexts["Start a new game?"]
            let fits = app.windows.firstMatch.frame.contains(card.frame)
            let height = title.frame.height
            app.terminate()
            return (height, fits)
        }
        let (standard, _) = titleHeight([])
        let (larger, fits) = titleHeight(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertGreaterThan(larger, standard * 1.4, "the title grows with Larger Text")
        XCTAssertTrue(fits, "the card stays on screen")
    }
    #endif

    /// The question before losing a game: the dark card (spec "Colours and dialogs"). Nil if none
    /// appears within `timeout`.
    @discardableResult
    private func confirmation(_ app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement? {
        let card = app.descendants(matching: .any)["confirmation"]
        return card.waitForExistence(timeout: timeout) ? card : nil
    }

    /// The seven face-up column cards, which identify a deal.
    private func dealSignature(_ app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', column '"))
            .allElementsBoundByIndex.map(\.label)
    }

    /// The waste top's label ("7 of Clubs, waste"), to compare boards across a relaunch.
    private func wasteTop(_ app: XCUIApplication) -> String? {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH ', waste'"))
            .allElementsBoundByIndex.last?.label
    }

    /// An element whose text is `string`. The toolbar's counters are StaticTexts whose text iOS
    /// exposes as the accessibility label and macOS as the value, so match either.
    private func text(_ app: XCUIApplication, equalTo string: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", string, string)).firstMatch
    }

    /// Elapsed seconds from the clock's spoken text ("Time 0 minutes 7 seconds").
    private func seconds(_ app: XCUIApplication) throws -> Int {
        let clock = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Time ' OR value BEGINSWITH 'Time '")).firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5), "the clock")
        let spoken = clock.label.hasPrefix("Time ") ? clock.label : (clock.value as? String ?? "")
        let words = spoken.split(separator: " ")
        guard words.count >= 4, let minutes = Int(words[1]), let secs = Int(words[3]) else {
            XCTFail("unexpected clock text: \(spoken)")         // fail, never skip: a skip would hide it
            return -1
        }
        return minutes * 60 + secs
    }

    /// How to Play opens from where the spec's help lives on each platform: Help ▸ Solitaire Help
    /// on the Mac (a window), More ▸ How to Play on iPhone (a sheet, closed with Done).
    func testHowToPlayOpens() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        #if os(macOS)
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Solitaire Help"].click()
        XCTAssertTrue(app.windows["How to Play"].waitForExistence(timeout: 5), "the help window")
        XCTAssertTrue(text(app, equalTo: "Goal").exists)
        #else
        more(app, "How to Play")
        XCTAssertTrue(text(app, equalTo: "Goal").waitForExistence(timeout: 5), "the help sheet")
        app.buttons["Done"].press()
        XCTAssertTrue(text(app, equalTo: "Goal").waitForNonExistence(timeout: 5), "Done closes it")
        #endif
    }

    /// Settings, from More: a face and back chosen there apply at once and are remembered.
    func testSettingsChooseTheCardStyleAndRememberIt() {
        var app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "Settings")
        let night = app.buttons["Night"].firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Three cards"].exists, "the draw mode is the chip's, not a setting")
        // The picker: labelled "Animation" on iPhone; on the Mac it shows its choice.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Animation' OR label == 'Cascade' OR value == 'Cascade'")).firstMatch.exists,
                      "the win animation picker")
        XCTAssertFalse(night.isSelected, "Classic is the default")
        night.press()
        XCTAssertTrue(night.isSelected)
        revealInSettings(app, "Art Deco").press()
        app.terminate()
        app = launch(seed: 4, reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "Settings")
        XCTAssertTrue(app.buttons["Night"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Night"].firstMatch.isSelected, "remembered")
        XCTAssertTrue(revealInSettings(app, "Art Deco").isSelected, "remembered")
    }

    /// A saved face or back this version doesn't know (from an older or newer one) reads as the
    /// default rather than breaking the cards or Settings.
    func testUnknownSavedCardStyleFallsBackToTheDefault() {
        let app = launch(seed: 4, arguments: ["-cardFace", "tartan", "-cardBack", "plaid"])
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "Settings")
        XCTAssertTrue(app.buttons["Classic"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Classic"].firstMatch.isSelected, "face falls back to Classic")
        XCTAssertTrue(revealInSettings(app, "Classic Blue").isSelected, "back falls back to Classic Blue")
    }

    /// A button in Settings, scrolled into view: iPhone's Settings sheet is taller than the screen
    /// and iOS doesn't make rows that are off it. The Mac's Settings window shows everything.
    @discardableResult
    private func revealInSettings(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let button = app.buttons[label].firstMatch
        #if os(iOS)
        for _ in 0..<6 where !(button.exists && button.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        #endif
        XCTAssertTrue(button.waitForExistence(timeout: 3), "\(label) in Settings")
        return button
    }

    /// About, from More: the version and the links to the site, the privacy policy and support.
    func testAboutShowsTheVersionAndLinks() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        more(app, "About")
        // iOS exposes static text as its label, macOS as its value.
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                                                           "Version 1.1", "Version 1.1")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5), "the version line")
        for link in ["One Off Endeavors", "Privacy policy", "Support and feedback"] {
            XCTAssertTrue(app.descendants(matching: .any)[link].firstMatch.exists, link)
        }
    }

    /// The draw pile on the right (spec "Top row"): set in Settings, applied at once, remembered;
    /// the stock still draws from there. An unknown saved side reads as left.
    func testDrawPileCanSitOnTheRight() {
        var app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        XCTAssertEqual(stockSide(app), "left", "left by default")
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Draw pile on the right")
        XCTAssertNotNil(toggle)
        toggle?.press()
        closeSettings(app)
        XCTAssertEqual(stockSide(app), "right", "moved to the right at once")
        app.terminate()
        app = launch(seed: 4, reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        XCTAssertEqual(stockSide(app), "right", "remembered")
        app.descendants(matching: .any)["Stock, 24 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5), "draws on the right")
        app.terminate()
        app = launch(seed: 4, arguments: ["-drawPileSide", "sideways"])
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        XCTAssertEqual(stockSide(app), "left", "an unknown saved side reads as left")
    }

    /// Which side the stock is on: "left" when it is wholly left of every foundation, "right" when
    /// wholly right of them all, nil for anything else (e.g. on top of one).
    private func stockSide(_ app: XCUIApplication) -> String? {
        let stock = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Stock'")).firstMatch.frame
        let foundations = (1...4).map { app.descendants(matching: .any)["Foundation \($0), empty"].frame }
        if foundations.allSatisfy({ stock.maxX <= $0.minX }) { return "left" }
        if foundations.allSatisfy({ stock.minX >= $0.maxX }) { return "right" }
        return nil
    }

    /// The control of a switch in Settings. iPhone and iPad: the switch inside the labelled row (a
    /// tap on the row's middle doesn't flip it). Mac: the switch has no label of its own — the
    /// words are a separate text — so it is the switch on that text's line.
    private func settingsSwitch(_ app: XCUIApplication, _ label: String) -> XCUIElement? {
        #if os(macOS)
        let text = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", label, label)).firstMatch
        guard text.waitForExistence(timeout: 5) else { return nil }
        return app.switches.allElementsBoundByIndex.first { abs($0.frame.midY - text.frame.midY) < 6 }
        #else
        let row = app.switches[label].firstMatch
        guard row.waitForExistence(timeout: 5) else { return nil }
        return row.switches.firstMatch.exists ? row.switches.firstMatch : row
        #endif
    }

    private func closeSettings(_ app: XCUIApplication) {
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)              // the Settings window is in front
        #else
        app.buttons["Done"].firstMatch.press()
        #endif
        sleep(1)
    }

    /// Opens More and chooses `item`, a tile on the More card.
    private func more(_ app: XCUIApplication, _ item: String) {
        let button = app.buttons["More"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press()
        let card = app.descendants(matching: .any)["moreCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the More card")
        let entry = card.buttons[item].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), item)
        entry.press()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "choosing a tile closes the card")
    }

    /// More is a dark card of tiles (spec "Settings, About and the More menu"); Close and a tap on
    /// the dimmed table both close it without opening anything.
    func testMoreIsACardOfTiles() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        let card = app.descendants(matching: .any)["moreCard"]
        app.buttons["More"].firstMatch.press()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for tile in ["How to Play", "Scores", "Settings", "About"] {
            XCTAssertTrue(card.buttons[tile].exists, tile)
        }
        card.buttons["Close"].press()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "Close")
        app.buttons["More"].firstMatch.press()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "a tap outside")
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].exists, "nothing else happened")
    }

    /// A tap on the stock draws; undo puts it back.
    func testDrawAndUndo() {
        let app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        app.buttons["Undo"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
    }
}

/// On macOS 27, XCUITest's `tap()` no longer reaches AppKit/SwiftUI controls: "Synthesize event"
/// takes seconds and the control never acts. `click()` still works but exists only on macOS, so
/// these pick the right gesture per platform.
extension XCUICoordinate {
    func press() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }
}

extension XCUIElement {
    func press() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }

    /// Drags from `grabAt` (a fraction of the height from the top) to the target's centre. A card
    /// under others in a fan shows only its top strip; grabbing its centre picks up a card below.
    func drag(to target: XCUIElement, grabAt y: CGFloat = 0.5) {
        let from = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
        let to = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        #if os(macOS)
        from.click(forDuration: 0.2, thenDragTo: to)
        #else
        from.press(forDuration: 0.2, thenDragTo: to)
        #endif
    }
}
