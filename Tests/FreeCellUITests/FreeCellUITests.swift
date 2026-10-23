import XCTest

/// End-to-end checks in the running app (XCUITest drives real taps and drags). Most start from game
/// 1, whose deal is Microsoft's published one, so the cards they name are known:
/// the last cards of its columns are 6♠ 9♣ 2♥ 6♥ 6♣ 3♦ 8♣ 10♣.
@MainActor
final class FreeCellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The UI tests' own save file and settings suite: no UI test reads or overwrites the player's
    /// real game or preferences (on the Mac they share the real app's container). One fixed name,
    /// reset at the start of each test, so runs never leave files piling up.
    private let isolation = "uitest"

    /// Launches the app with a Debug scenario or game number, passed in the environment (see
    /// UITestScenario; with a number, New Game deals the next ones in turn). `reset: false` keeps
    /// the previous launch's save — for relaunch tests. `arguments` are extra launch arguments,
    /// e.g. `["-cardFace", "night"]` to put a value in the arguments domain, which every
    /// UserDefaults read sees first.
    private func launch(scenario: String? = nil, game: Int? = nil, reset: Bool = true,
                        arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FREECELL_SAVE_FILE"] = isolation
        app.launchEnvironment["FREECELL_DEFAULTS_SUITE"] = isolation
        if reset { app.launchEnvironment["FREECELL_RESET"] = "1" }
        // Ignore saved window state, as Xcode does for the unit-test host. A run that quit with no
        // window open saves "no windows", and XCUITest's launch (unlike Finder or the Dock) does not
        // send the "open application" event that would open one anyway — the app came up windowless.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + arguments
        if let scenario { app.launchEnvironment["FREECELL_SCENARIO"] = scenario }
        if let game { app.launchEnvironment["FREECELL_GAME"] = String(game) }
        app.launch()
        return app
    }

    /// Any element with this accessibility label.
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)[label].firstMatch
    }

    /// The header's game chip.
    private func chip(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["gameChip"].firstMatch
    }

    /// Waits for the board, by its game chip; returns the chip.
    @discardableResult
    private func board(_ app: XCUIApplication) -> XCUIElement {
        let c = chip(app)
        XCTAssertTrue(c.waitForExistence(timeout: 5), "the board")
        return c
    }

    /// Game 1's 6♥, the last card of column 4: a tap sends it to the first free cell.
    private func moveTheSixOfHeartsToACell(_ app: XCUIApplication) {
        element(app, "6 of Hearts, column 4").press()
        XCTAssertTrue(element(app, "6 of Hearts, free cell 1").waitForExistence(timeout: 5), "into a free cell")
    }

    /// Acceptance: a game played to a win shows the win card with its time and moves — after the
    /// win animation, which it must not cover; a click on the animation skips straight to it.
    func testFinishWinsAndShowsTheWinCard() {
        let app = launch(scenario: "almostWon")
        let finish = app.buttons["Auto-finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "Finish should be offered")
        finish.press()
        XCTAssertTrue(text(app, equalTo: "0 moves").waitForExistence(timeout: 5), "Finish's steps cost no moves")
        XCTAssertFalse(app.staticTexts["You won!"].waitForExistence(timeout: 3), "the animation plays uncovered")
        // Skip it with a click on the board. (A point, not the window element: on the Mac
        // XCUITest's click on a window never reaches its content.)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 5))
        let card = app.descendants(matching: .any)["winCard"]
        XCTAssertTrue(card.exists, "the win card")
        XCTAssertTrue(card.buttons["New Game"].exists && card.buttons["Choose a game"].exists && card.buttons["Top 10"].exists)
        for figure in ["0 undos", "4 free cells", "1 win"] {
            XCTAssertTrue(card.descendants(matching: .any)[figure].exists, figure)
        }
        XCTAssertTrue(card.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Time '")).firstMatch.exists,
                      "the time on the win card")
        // The first win of a fresh Top 10 is #1 (spec "Scores"); Top 10 opens Scores.
        let badge = card.descendants(matching: .any)["topTenBadge"]
        XCTAssertTrue(badge.exists, "the New Top 10 badge")
        // Text is a label on iPhone and a value on the Mac: read whichever is set.
        XCTAssertEqual(badge.label.isEmpty ? "\(badge.value ?? "")" : badge.label, "New Top 10 · #1")
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
            XCTAssertFalse(app.staticTexts["You won!"].waitForExistence(timeout: 2), "\(animation) plays uncovered")
            XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 30), "\(animation) ends in the win card")
            app.terminate()
        }
        let app = launch(scenario: "almostWon", arguments: ["-winAnimation", "none"])
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        app.buttons["Auto-finish"].press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 6), "None: the win card at once")
    }

    /// Left alone, the cascade runs to its end and then the win card appears.
    func testWinCardFollowsTheCascade() {
        let app = launch(scenario: "almostWon")
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        app.buttons["Auto-finish"].press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 60), "the cascade should end")
    }

    /// A tap sends a card to its best spot — here a free cell — and Undo puts it back.
    func testATapMovesACardAndUndoPutsItBack() {
        let app = launch(game: 1)
        board(app)
        moveTheSixOfHeartsToACell(app)
        XCTAssertTrue(text(app, equalTo: "1 moves").exists || text(app, equalTo: "1 move").exists, "one move")
        app.buttons["Undo"].press()
        XCTAssertTrue(element(app, "6 of Hearts, column 4").waitForExistence(timeout: 5), "back in its column")
        XCTAssertTrue(element(app, "Free cell 1, empty").exists)
    }

    /// The run limit in the app (spec "Game rules"): the whole K→A run lifts but springs back from
    /// the one empty column — five cards fit there — and a five-card run moves, its ace then going
    /// home by itself.
    func testTheRunLimitInTheApp() {
        let app = launch(scenario: "kingToAce")
        let king = element(app, "King of Spades, column 1")
        XCTAssertTrue(king.waitForExistence(timeout: 5))
        king.drag(to: element(app, "Column 2, empty"), grabAt: 0.08)          // its visible strip
        sleep(1)
        XCTAssertTrue(element(app, "King of Spades, column 1").exists, "thirteen cards: refused, back in column 1")
        let notice = app.descendants(matching: .any)["runLimitNotice"]
        XCTAssertTrue(notice.exists || notice.waitForExistence(timeout: 2), "the board says why")
        let said = notice.label.isEmpty ? "\(notice.value ?? "")" : notice.label
        XCTAssertEqual(said, "Only 5 cards can move into an empty column — 4 free cells, no other empty column")
        XCTAssertTrue(element(app, "Column 2, empty").exists)
        element(app, "5 of Spades, column 1").drag(to: element(app, "Column 2, empty"), grabAt: 0.08)
        XCTAssertTrue(element(app, "5 of Spades, column 2").waitForExistence(timeout: 5), "five cards move")
        XCTAssertTrue(element(app, "Ace of Spades, foundation 1").waitForExistence(timeout: 5),
                      "the ace, now last in its column, plays home by itself")
    }

    #if os(macOS)
    /// The menus follow the game: Undo enables after a move, Finish only when it is offered.
    func testMenuItemsFollowTheGame() {
        let app = launch(scenario: "almostWon")
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        func menuItem(_ menu: String, _ item: String) -> XCUIElement {
            app.menuBars.menuBarItems[menu].click()
            return app.menuBars.menuItems[item]
        }
        XCTAssertTrue(menuItem("Game", "Finish").isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(menuItem("Edit", "Undo").isEnabled, "nothing to undo yet")
        app.typeKey(.escape, modifierFlags: [])
        element(app, "Jack of Spades, column 4").press()                      // one move to a foundation
        XCTAssertTrue(menuItem("Edit", "Undo").isEnabled, "a move can be undone")
        app.typeKey(.escape, modifierFlags: [])
    }
    #endif

    /// Acceptance: force-quitting mid-game and relaunching restores the same board, game number,
    /// move count and elapsed time.
    func testForceQuitAndRelaunchRestoresTheGame() throws {
        var app = launch(game: 1)
        board(app)
        moveTheSixOfHeartsToACell(app)
        element(app, "6 of Spades, column 1").press()
        XCTAssertTrue(element(app, "6 of Spades, free cell 2").waitForExistence(timeout: 5))
        sleep(6)                                          // the clock passes a five-second save
        let before = try seconds(app)
        XCTAssertGreaterThanOrEqual(before, 5)

        app.terminate()                                   // force quit: no chance to save
        app = launch(reset: false)                        // same save file, no number: resume
        XCTAssertTrue(element(app, "6 of Spades, free cell 2").waitForExistence(timeout: 5), "same board")
        XCTAssertTrue(element(app, "6 of Hearts, free cell 1").exists)
        XCTAssertEqual(chip(app).label, "Game 1", "same game")
        XCTAssertTrue(text(app, equalTo: "2 moves").exists, "move count restored")
        // Restored to the last save — at most five seconds back. The clock runs again once
        // relaunched, so allow for the relaunch itself (slower on iOS) above.
        let after = try seconds(app)
        XCTAssertTrue((before - 5)...(before + Self.relaunchSlack) ~= after,
                      "elapsed \(after) s after quitting at \(before) s")
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "a resumed game starts with undo empty")
    }

    /// Quitting normally (⌘Q on the Mac; iOS sending the app to the background) saves on the spot,
    /// so the elapsed time comes back exactly — not rounded down to the last five-second save.
    func testQuittingNormallyKeepsTheExactTime() throws {
        var app = launch(game: 1)
        board(app)
        moveTheSixOfHeartsToACell(app)
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
        XCTAssertTrue(element(app, "6 of Hearts, free cell 1").waitForExistence(timeout: 5))
        let after = try seconds(app)
        XCTAssertTrue(before...(before + Self.relaunchSlack) ~= after,
                      "elapsed \(after) s after quitting at \(before) s")
    }

    /// Seconds the clock keeps running around a quit and relaunch (quit ~1 s, iOS relaunch ~3 s).
    private static let relaunchSlack = 6

    /// New Game deals at once on a fresh deal; mid-game it asks, and Cancel keeps the game.
    func testNewGameAsksOnlyWhenAGameWouldBeLost() {
        let app = launch(game: 1)
        XCTAssertEqual(board(app).label, "Game 1")
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNil(confirmation(app, timeout: 2), "nothing to lose on a fresh deal: no question")
        XCTAssertEqual(chip(app).label, "Game 2", "dealt at once")
        app.buttons["New Game"].firstMatch.press()                              // game 3, fresh
        XCTAssertEqual(chip(app).label, "Game 3")
        element(app, "8 of Clubs, column 1").press()                            // game 3's: to a cell
        XCTAssertTrue(element(app, "8 of Clubs, free cell 1").waitForExistence(timeout: 5), "a move")
        app.buttons["New Game"].firstMatch.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, New Game asks first")
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(chip(app).label, "Game 3", "Cancel keeps the game")
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNotNil(confirmation(app))
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press()
        XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3),
                      "a tap on the dimmed table cancels")
        XCTAssertEqual(chip(app).label, "Game 3", "and keeps the game")
        #if os(macOS)
        // The question is modal: ⌘Z doesn't reach the game behind it.
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNotNil(confirmation(app))
        app.typeKey("z", modifierFlags: .command)
        sleep(1)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3), "Esc cancels")
        XCTAssertTrue(app.buttons["Undo"].isEnabled, "⌘Z didn't reach the game")
        #endif
        app.buttons["New Game"].firstMatch.press()
        confirmation(app)?.buttons["New Game"].press()
        XCTAssertTrue(chip(app).waitForExistence(timeout: 5))
        XCTAssertEqual(chip(app).label, "Game 4", "confirmed: a new deal")
    }

    /// Choose a game (spec "New games"): the header chip opens it; Play deals the number typed —
    /// without a second question mid-game, the card having said so; Random game deals another.
    func testChooseAGameByNumber() {
        let app = launch(game: 1)
        board(app)
        moveTheSixOfHeartsToACell(app)
        chip(app).press()
        let card = app.descendants(matching: .any)["chooseGame"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the chip opens Choose a game")
        XCTAssertTrue(card.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@",
            "The game in progress will end.", "The game in progress will end.")).firstMatch.exists, "mid-game, it says so")
        let field = card.descendants(matching: .any)["gameNumber"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.press()
        field.typeText("617")
        let play = card.buttons["Play Game 617"]
        XCTAssertTrue(play.waitForExistence(timeout: 3), "the button names the game")
        play.press()
        XCTAssertNil(confirmation(app, timeout: 2), "no second question")
        XCTAssertEqual(chip(app).label, "Game 617")
        XCTAssertTrue(element(app, "Jack of Diamonds, column 1").exists, "Microsoft's game 617 (its column 1 ends J♦)")
        #if os(macOS)
        app.typeKey("n", modifierFlags: [.command, .shift])
        #else
        chip(app).press()
        #endif
        XCTAssertTrue(card.waitForExistence(timeout: 5), "⇧⌘N on the Mac, the chip on iPhone")
        card.buttons["Random game"].press()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
        XCTAssertEqual(chip(app).label, "Game 2", "the next number in the test's sequence")
        chip(app).press()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.buttons["Cancel"].press()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
        XCTAssertEqual(chip(app).label, "Game 2", "Cancel changes nothing")
    }

    /// Settings ▸ Ask before ending a game, turned off: New Game mid-game deals at once, and the
    /// choice survives a relaunch.
    func testAskingCanBeTurnedOff() {
        var app = launch(game: 1)
        board(app)
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Ask before ending a game")
        XCTAssertNotNil(toggle)
        // A switch's value is "1" on iPhone and the number 1 on the Mac: compare as text.
        XCTAssertEqual(toggle.map { "\($0.value ?? "")" }, "1", "on by default")
        toggle?.press()
        closeSettings(app)
        moveTheSixOfHeartsToACell(app)
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNil(confirmation(app, timeout: 2), "no question")
        XCTAssertEqual(chip(app).label, "Game 2", "dealt at once")
        app.terminate()
        app = launch(game: 1, reset: false)
        board(app)
        moveTheSixOfHeartsToACell(app)
        app.buttons["New Game"].firstMatch.press()
        XCTAssertNil(confirmation(app, timeout: 2), "still off after a relaunch")
        XCTAssertEqual(chip(app).label, "Game 2")
    }

    /// Restart (spec "Restart"): no button until Settings ▸ Restart button is on; then it is off on
    /// a fresh deal, asks mid-game, and deals the same game again; the setting survives a relaunch.
    func testRestart() {
        var app = launch(game: 1)
        board(app)
        XCTAssertFalse(app.buttons["Restart"].exists, "off by default")
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Restart button")
        XCTAssertEqual(toggle.map { "\($0.value ?? "")" }, "0", "off by default")
        toggle?.press()
        closeSettings(app)
        let restart = app.buttons["Restart"].firstMatch
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "in the bar")
        XCTAssertFalse(restart.isEnabled, "a fresh deal is already the start")
        moveTheSixOfHeartsToACell(app)
        restart.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, it asks")
        XCTAssertTrue(ask?.staticTexts["Restart this game?"].exists ?? false)
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(element(app, "6 of Hearts, free cell 1").waitForExistence(timeout: 3), "Cancel keeps the game")
        restart.press()
        confirmation(app)?.buttons["Restart"].press()
        XCTAssertTrue(element(app, "6 of Hearts, column 4").waitForExistence(timeout: 5), "from the start")
        XCTAssertEqual(chip(app).label, "Game 1", "the same game")
        #if os(macOS)
        moveTheSixOfHeartsToACell(app)
        app.typeKey("r", modifierFlags: .command)
        XCTAssertNotNil(confirmation(app), "⌘R restarts too")
        app.typeKey(.escape, modifierFlags: [])
        #endif
        app.terminate()
        app = launch(game: 1, reset: false)
        XCTAssertTrue(app.buttons["Restart"].firstMatch.waitForExistence(timeout: 5), "still on after a relaunch")
    }

    /// Hard Core (spec "Hard Core"): the Settings switch deals a Hard Core game at once on a fresh
    /// deal — two free cells, the other two closed; turning it off mid-game asks, and Cancel keeps
    /// the Hard Core game.
    func testHardCore() {
        let app = launch(game: 1)
        board(app)
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Hard Core")
        XCTAssertNotNil(toggle)
        toggle?.press()
        XCTAssertNil(confirmation(app, timeout: 1), "a fresh deal: no question")
        XCTAssertTrue(chip(app).waitForExistence(timeout: 5))
        XCTAssertEqual(chip(app).label, "Game 2, Hard Core", "Settings closed and a Hard Core game was dealt")
        XCTAssertTrue(element(app, "Free cell 3, closed").exists && element(app, "Free cell 4, closed").exists)
        XCTAssertTrue(element(app, "Free cell 2, empty").exists)
        element(app, "10 of Hearts, column 3").press()                          // game 2's: to a cell
        XCTAssertTrue(element(app, "10 of Hearts, free cell 1").waitForExistence(timeout: 5), "a move")
        more(app, "Settings")
        settingsSwitch(app, "Hard Core")?.press()
        let ask = confirmation(app)
        XCTAssertNotNil(ask, "mid-game, turning it off asks")
        XCTAssertTrue(ask?.staticTexts["Turn off Hard Core?"].exists ?? false)
        ask?.buttons["Cancel"].press()
        XCTAssertTrue(app.descendants(matching: .any)["confirmation"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(chip(app).label, "Game 2, Hard Core", "Cancel keeps it")
    }

    /// Relaxed (spec "Relaxed"): the Settings switch deals a Relaxed game at once on a fresh deal,
    /// and the chip says so.
    func testRelaxed() {
        let app = launch(game: 1)
        board(app)
        more(app, "Settings")
        let toggle = settingsSwitch(app, "Relaxed")
        XCTAssertNotNil(toggle)
        toggle?.press()
        XCTAssertNil(confirmation(app, timeout: 1), "a fresh deal: no question")
        XCTAssertTrue(chip(app).waitForExistence(timeout: 5))
        XCTAssertEqual(chip(app).label, "Game 2, Relaxed")
    }

    /// Scores from More, before any win: an empty Top 10 says so, and Game Center is off.
    func testScoresStartEmpty() {
        let app = launch(game: 1)
        board(app)
        more(app, "Scores")
        let scores = app.descendants(matching: .any)["scores"]
        XCTAssertTrue(scores.waitForExistence(timeout: 5))
        XCTAssertTrue(scores.staticTexts["No wins yet."].exists)
        // Separate text on iPhone; part of the board row's label on the Mac.
        XCTAssertTrue(scores.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Not signed in'")).firstMatch.exists,
                      "Game Center is off under tests")
    }

    /// The header: time, moves and the game chip — no score.
    func testTheHeaderShowsTheGame() {
        let app = launch(game: 24301)
        XCTAssertEqual(board(app).label, "Game 24301")
        XCTAssertTrue(text(app, equalTo: "0 moves").exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Score '")).firstMatch.exists,
                       "FreeCell has no score")
    }

    #if os(macOS)
    /// Closing the game window quits the app — even with another of its windows open — so ⌘N can
    /// never act on a game that isn't on screen.
    func testClosingTheGameWindowQuits() {
        let app = launch(game: 1)
        board(app)
        more(app, "About")
        XCTAssertTrue(app.windows["About FreeCell"].waitForExistence(timeout: 5))
        let game = app.windows.matching(NSPredicate(format: "title == 'FreeCell'")).firstMatch
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
            let app = launch(game: 1, arguments: arguments)
            board(app)
            moveTheSixOfHeartsToACell(app)
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

    /// An element whose text is `string`. The header's counters are StaticTexts whose text iOS
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

    /// How to Play opens from where the spec's help lives on each platform: Help ▸ FreeCell Help
    /// on the Mac (a window), More ▸ How to Play on iPhone (a sheet, closed with Done).
    func testHowToPlayOpens() {
        let app = launch(game: 1)
        board(app)
        #if os(macOS)
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["FreeCell Help"].click()
        XCTAssertTrue(app.windows["How to Play"].waitForExistence(timeout: 5), "the help window")
        XCTAssertTrue(text(app, equalTo: "Goal").exists)
        #else
        more(app, "How to Play")
        XCTAssertTrue(text(app, equalTo: "Goal").waitForExistence(timeout: 5), "the help sheet")
        app.buttons["Done"].press()
        XCTAssertTrue(text(app, equalTo: "Goal").waitForNonExistence(timeout: 5), "Done closes it")
        #endif
    }

    /// Settings, from More: a face and back chosen there apply at once and are remembered; the
    /// FreeCell switches are there.
    func testSettingsChooseTheCardStyleAndRememberIt() {
        var app = launch(game: 1)
        board(app)
        more(app, "Settings")
        let night = app.buttons["Night"].firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 5))
        XCTAssertNotNil(settingsSwitch(app, "Play cards home automatically"), "the automatic plays switch")
        XCTAssertFalse(app.descendants(matching: .any)["Draw pile on the right"].exists, "Klondike's setting is gone")
        // The picker: labelled "Animation" on iPhone; on the Mac it shows its choice.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Animation' OR label == 'Cascade' OR value == 'Cascade'")).firstMatch.exists,
                      "the win animation picker")
        XCTAssertFalse(night.isSelected, "Classic is the default")
        night.press()
        XCTAssertTrue(night.isSelected)
        revealInSettings(app, "Art Deco").press()
        app.terminate()
        app = launch(game: 1, reset: false)
        board(app)
        more(app, "Settings")
        XCTAssertTrue(app.buttons["Night"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Night"].firstMatch.isSelected, "remembered")
        XCTAssertTrue(revealInSettings(app, "Art Deco").isSelected, "remembered")
    }

    /// A saved face or back this version doesn't know reads as the default rather than breaking
    /// the cards or Settings.
    func testUnknownSavedCardStyleFallsBackToTheDefault() {
        let app = launch(game: 1, arguments: ["-cardFace", "tartan", "-cardBack", "plaid"])
        board(app)
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
        let app = launch(game: 1)
        board(app)
        more(app, "About")
        // iOS exposes static text as its label, macOS as its value.
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                                                           "Version 1.0", "Version 1.0")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5), "the version line")
        for link in ["One Off Endeavors", "Privacy policy", "Support and feedback"] {
            XCTAssertTrue(app.descendants(matching: .any)[link].firstMatch.exists, link)
        }
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
        let app = launch(game: 1)
        board(app)
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
        XCTAssertEqual(chip(app).label, "Game 1", "nothing else happened")
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
