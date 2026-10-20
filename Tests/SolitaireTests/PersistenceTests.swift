import Foundation
import Testing
import SolitaireEngine
@testable import Solitaire

private func tempSaveURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("solitaire-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("game.json")
}

@Suite struct Resumability {
    let game = SolitaireEngine.newGame(drawCount: 1, seed: 4)

    @Test func aRealGameIsResumable() {
        #expect(SaveValidation.isResumable(game))
    }

    /// Anything invalid is discarded (spec: 52 distinct cards, not already won; decision F6: 4
    /// foundations and 7 columns) — plus a valid draw mode and sane counters.
    @Test(arguments: [
        "won", "3 foundations", "8 columns", "51 cards", "duplicate card", "rank 14", "draw 2",
        "negative moves", "negative time", "negative redeals", "more redeals than moves",
        "hard core past its passes", "negative undos",
        "face-down column top", "face-up stock", "face-down waste", "foundation out of order",
        "mixed foundation", "unbuilt run",
    ])
    func invalidSavesAreRejected(_ defect: String) {
        var s = game
        switch defect {
        case "won": s.isWon = true
        case "3 foundations": s.foundations.removeLast()
        case "8 columns": s.tableau.append([])
        case "51 cards": s.stock.removeLast()
        case "duplicate card": s.stock[0] = s.stock[1]
        case "rank 14": s.stock[0] = Card(suit: .clubs, rank: 14)
        case "draw 2": s.drawCount = 2
        case "negative moves": s.moveCount = -1
        case "negative time": s.elapsed = -1
        case "negative redeals": s.redeals = -1
        case "more redeals than moves": s.moveCount = 3; s.redeals = 4
        case "hard core past its passes": s.isHardCore = true; s.drawCount = 1; s.moveCount = 30; s.redeals = 1
        case "negative undos": s.undos = -1
        case "face-down column top": s.tableau[6][6].isFaceUp = false
        case "face-up stock": s.stock[0].isFaceUp = true
        case "face-down waste":
            SolitaireEngine.drawFromStock(&s)
            s.waste[0].isFaceUp = false
        case "foundation out of order", "mixed foundation", "unbuilt run":
            // Rebuild the piles by hand from a legal, spread-out position.
            s = board(defect)
        default: Issue.record("unknown defect")
        }
        #expect(!SaveValidation.isResumable(s), "\(defect)")
    }
}

/// A 52-card position laid out by hand, with one structural defect.
private func board(_ defect: String) -> GameState {
    var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
    var all = (s.stock + s.tableau.flatMap { $0 }).map { c -> Card in var c = c; c.isFaceUp = false; return c }
    func take(_ suit: Suit, _ rank: Int) -> Card {
        let i = all.firstIndex { $0.suit == suit && $0.rank == rank }!
        var c = all.remove(at: i); c.isFaceUp = true; return c
    }
    s.foundations = [[], [], [], []]
    s.tableau = Array(repeating: [], count: 7)
    switch defect {
    case "foundation out of order":
        s.foundations[0] = [take(.spades, 1), take(.spades, 3)]
    case "mixed foundation":
        s.foundations[0] = [take(.spades, 1), take(.hearts, 2)]
    default:                                              // "unbuilt run": 9♥ under 8♥ (same colour)
        s.tableau[0] = [take(.hearts, 9), take(.hearts, 8)]
    }
    s.stock = all
    s.waste = []
    return s
}

@Suite struct ResumabilityOfRealPlay {
    /// Validation must never reject a position real play produces (or a resumed game would be
    /// thrown away): every state along 40 random games passes.
    @Test func everyPositionFromRealPlayIsResumable() {
        var checked = 0
        for seed in UInt64(1)...40 {
            var s = SolitaireEngine.newGame(drawCount: seed % 2 == 0 ? 1 : 3, seed: seed)
            var rng = SplitMix64(seed: seed)
            for _ in 0..<250 where !s.isWon {
                #expect(SaveValidation.isResumable(s), "seed \(seed) move \(s.moveCount)")
                checked += 1
                let moves = legalMoves(s)
                if !moves.isEmpty && rng.next() % 3 != 0 {
                    SolitaireEngine.apply(moves[Int(rng.next() % UInt64(moves.count))], to: &s)
                } else {
                    SolitaireEngine.drawFromStock(&s)
                }
            }
        }
        #expect(checked > 5000)
    }
}

@Suite struct Saving {
    let game = SolitaireEngine.newGame(drawCount: 3, seed: 9)

    @Test func aSaveRoundTrips() async throws {
        let url = tempSaveURL()
        let saver = GameSaver(url: url)
        var s = game
        SolitaireEngine.drawFromStock(&s)
        s.elapsed = 42
        try await saver.save(s, sequence: 1)
        #expect(GameSaver.load(from: url) == s)
    }

    /// Saves may land out of order; a late, older one must not overwrite a newer one.
    @Test func anOlderSaveNeverOverwritesANewerOne() async throws {
        let url = tempSaveURL()
        let saver = GameSaver(url: url)
        var newer = game
        newer.moveCount = 5
        try await saver.save(newer, sequence: 2)
        try await saver.save(game, sequence: 1)
        #expect(GameSaver.load(from: url)?.moveCount == 5)
    }

    /// A save in a format this version does not know is discarded, not misread.
    @Test func anUnknownFormatVersionLoadsAsNothing() async throws {
        let url = tempSaveURL()
        try await GameSaver(url: url).save(game, sequence: 1)
        #expect(GameSaver.load(from: url) == game)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"version\":1") && text.contains("savedAt"))
        try text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
            .write(to: url, atomically: true, encoding: .utf8)
        #expect(GameSaver.load(from: url) == nil)
    }

    @Test func missingCorruptOrWonSavesLoadAsNothing() async throws {
        let url = tempSaveURL()
        #expect(GameSaver.load(from: url) == nil, "missing")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(GameSaver.load(from: url) == nil, "corrupt")
        var won = game
        won.isWon = true
        try await GameSaver(url: url).save(won, sequence: 1)
        #expect(GameSaver.load(from: url) == nil, "already won")
    }
}

@Suite struct Launching {
    let saved = SolitaireEngine.newGame(drawCount: 3, seed: 9)

    @Test func resumeWhenWantedAndPresent() {
        #expect(LaunchPlan.decide(saved: saved, resumePreferred: true, drawCount: 1) == .resume(saved))
    }

    @MainActor @Test func dealFreshOtherwiseInTheRememberedMode() {
        #expect(LaunchPlan.decide(saved: saved, resumePreferred: false, drawCount: 3) == .deal(drawCount: 3))
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, drawCount: 3) == .deal(drawCount: 3))
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, drawCount: 3, hardCore: true)
                == .deal(drawCount: 3, hardCore: true), "a fresh launch deals Hard Core if the last deal was")
        #expect(GameStore.launch(.deal(drawCount: 1, hardCore: true), drawCount: 1, saver: nil).state.isHardCore)
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, drawCount: 7) == .deal(drawCount: 1),
                "a corrupt setting is clamped")
    }

    /// A fresh deal at launch is saved at once, so an older game left on disk cannot come back.
    @MainActor @Test func aFreshDealIsSavedImmediately() async {
        let url = tempSaveURL()
        let store = GameStore.launch(.deal(drawCount: 3), drawCount: 3, saver: GameSaver(url: url))
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state)
    }

    /// UI tests reset their own save and settings; the player's game.json is never touched.
    @Test func testResetClearsOnlyTheTestsOwnData() throws {
        let env = ["SOLITAIRE_RESET": "1", "SOLITAIRE_SAVE_FILE": "uitest-reset-\(UUID().uuidString)",
                   "SOLITAIRE_DEFAULTS_SUITE": "uitest-reset-suite-\(UUID().uuidString)"]
        let url = try #require(SaveLocation.url(environment: env))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        let suite = try #require(UserDefaults(suiteName: env["SOLITAIRE_DEFAULTS_SUITE"]!))
        suite.set(3, forKey: AppSettings.drawCountKey)
        SaveLocation.resetForTests(environment: env)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(UserDefaults(suiteName: env["SOLITAIRE_DEFAULTS_SUITE"]!)?.object(forKey: AppSettings.drawCountKey) == nil)
        var withoutName = env
        withoutName["SOLITAIRE_SAVE_FILE"] = nil                   // would resolve to game.json
        let real = try #require(SaveLocation.url(environment: withoutName))
        let existed = FileManager.default.fileExists(atPath: real.path)
        SaveLocation.resetForTests(environment: withoutName)
        #expect(FileManager.default.fileExists(atPath: real.path) == existed, "game.json is never reset")
    }

    /// The unit-test host shares the real Mac app's container: it must never read or write the
    /// player's save. UI tests name their own file.
    @Test func testsNeverTouchTheRealSave() {
        #expect(SaveLocation.url(environment: ["XCTestConfigurationFilePath": "/x"]) == nil)
        #expect(SaveLocation.url(environment: [:])?.lastPathComponent == "game.json")
        #expect(SaveLocation.url(environment: ["SOLITAIRE_SAVE_FILE": "uitest-1"])?.lastPathComponent == "uitest-1.json")
        #expect(SaveLocation.url(environment: [:])?.deletingLastPathComponent().lastPathComponent == "Solitaire")
    }
}

@MainActor @Suite struct SaveTriggers {
    @Test func everyChangeSavesButTheClockOnlyEveryFiveSeconds() {
        let a = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        var drawn = a
        SolitaireEngine.drawFromStock(&drawn)
        #expect(GameStore.shouldSave(from: a, to: drawn), "a draw")
        var t = a
        for second in 1...10 {
            let before = t
            t.elapsed = Double(second)
            #expect(GameStore.shouldSave(from: before, to: t) == (second % 5 == 0), "tick \(second)")
        }
    }

    /// The draw-count setting is written whenever it changes — not from a view that may be gone.
    @Test func theDrawCountIsRememberedWheneverItChanges() {
        let store = makeStore()
        var remembered: [Int] = []
        store.rememberDrawCount = { remembered.append($0) }
        store.newGame(drawCount: 3)
        store.newGame(drawCount: 1)
        store.newGame(drawCount: 1)                                 // unchanged: not written again
        #expect(remembered == [3, 1])
    }

    /// Quitting or backgrounding waits until the save is on disk.
    @Test func flushingWaitsUntilTheSaveIsOnDisk() {
        let url = tempSaveURL()
        let store = makeStore()
        store.saver = GameSaver(url: url)
        store.tapStock()
        for _ in 0..<3 { store.tick() }                             // 3 s: not a save on its own
        store.flushSaves()
        #expect(GameSaver.load(from: url) == store.state, "on disk when flushSaves returns")
    }

    /// The store saves after a move and after undo — what a force-quit relaunch would find.
    @Test func theStoreSavesWhatItShows() async throws {
        let url = tempSaveURL()
        let store = makeStore()
        store.saver = GameSaver(url: url)
        store.tapStock()
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state)
        store.tapStock()
        store.undo()
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state, "after undo")
        for _ in 0..<5 { store.tick() }
        await store.lastSave?.value
        #expect(GameSaver.load(from: url)?.elapsed == 5, "the fifth second is saved")
    }
}
