import Foundation
import Testing
import FreeCellEngine
@testable import FreeCell

private func tempSaveURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("freecell-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("game.json")
}

@Suite struct Resumability {
    let game = FreeCellEngine.newGame(number: 617)

    @Test func aRealGameIsResumable() {
        #expect(SaveValidation.isResumable(game))
        #expect(SaveValidation.isResumable(FreeCellEngine.newGame(number: 617, hardCore: true)))
    }

    /// Anything invalid is discarded (spec "Persistence and settings"): 52 distinct cards, 8
    /// columns, 4 foundations, a cell count matching the mode, a number in range, not won.
    @Test(arguments: [
        "won", "3 foundations", "9 columns", "51 cards", "duplicate card", "rank 14", "number 0",
        "number too big", "hard core with four cells", "normal with two cells", "negative moves",
        "negative time", "negative undos", "foundation out of order", "mixed foundation",
    ])
    func invalidSavesAreRejected(_ defect: String) {
        var s = game
        switch defect {
        case "won": s.isWon = true
        case "3 foundations": s.foundations.removeLast()
        case "9 columns": s.tableau.append([])
        case "51 cards": s.tableau[0].removeLast()
        case "duplicate card": s.tableau[0][0] = s.tableau[0][1]
        case "rank 14": s.tableau[0][0] = Card(suit: .clubs, rank: 14)
        case "number 0": s.number = 0
        case "number too big": s.number = 1_000_001
        case "hard core with four cells": s.isHardCore = true
        case "normal with two cells": s.cells = [nil, nil]
        case "negative moves": s.moveCount = -1
        case "negative time": s.elapsed = -1
        case "negative undos": s.undos = -1
        case "foundation out of order", "mixed foundation":
            let pull = { (suit: Suit, rank: Int) -> Card in
                let c = Card(suit: suit, rank: rank)
                for t in s.tableau.indices { s.tableau[t].removeAll { $0 == c } }
                return c
            }
            s.foundations[0] = defect == "mixed foundation"
                ? [pull(.spades, 1), pull(.hearts, 2)] : [pull(.spades, 1), pull(.spades, 3)]
        default: Issue.record("unknown defect")
        }
        #expect(!SaveValidation.isResumable(s), "\(defect)")
    }
}

@Suite struct ResumabilityOfRealPlay {
    /// Validation must never reject a position real play produces (or a resumed game would be
    /// thrown away): every state along 40 random games — automatic plays included — passes.
    @Test func everyPositionFromRealPlayIsResumable() {
        var checked = 0
        for number in 1...40 {
            var s = FreeCellEngine.newGame(number: number, hardCore: number % 4 == 0)
            var rng = SplitMix64(seed: UInt64(number))
            for _ in 0..<150 where !s.isWon {
                #expect(SaveValidation.isResumable(s), "game \(number) move \(s.moveCount)")
                checked += 1
                let moves = randomPlayerMoves(s)
                guard !moves.isEmpty else { break }
                FreeCellEngine.apply(moves[Int(rng.next() % UInt64(moves.count))], to: &s)
                FreeCellEngine.settle(&s)
            }
        }
        #expect(checked > 3000)
    }
}

@Suite struct Saving {
    let game = FreeCellEngine.newGame(number: 9, hardCore: true)

    @Test func aSaveRoundTrips() async throws {
        let url = tempSaveURL()
        let saver = GameSaver(url: url)
        var s = game
        s.cells[0] = s.tableau[0].removeLast()
        s.elapsed = 42
        s.moveCount = 1
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
    let saved = FreeCellEngine.newGame(number: 9)

    @Test func resumeWhenWantedAndPresent() {
        #expect(LaunchPlan.decide(saved: saved, resumePreferred: true) == .resume(saved))
    }

    @MainActor @Test func dealFreshOtherwiseInTheRememberedMode() {
        #expect(LaunchPlan.decide(saved: saved, resumePreferred: false) == .deal(hardCore: false))
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, hardCore: true) == .deal(hardCore: true),
                "a fresh launch deals Hard Core if the last deal was")
        #expect(GameStore.launch(.deal(hardCore: true), saver: nil).state.isHardCore)
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, relaxed: true) == .deal(hardCore: false, relaxed: true))
        #expect(GameStore.launch(.deal(hardCore: false, relaxed: true), saver: nil).state.isRelaxed)
    }

    /// A fresh deal at launch is saved at once, so an older game left on disk cannot come back.
    @MainActor @Test func aFreshDealIsSavedImmediately() async {
        let url = tempSaveURL()
        let store = GameStore.launch(.deal(hardCore: false), saver: GameSaver(url: url))
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state)
    }

    /// UI tests reset their own save and settings; the player's game.json is never touched.
    @Test func testResetClearsOnlyTheTestsOwnData() throws {
        let env = ["FREECELL_RESET": "1", "FREECELL_SAVE_FILE": "uitest-reset-\(UUID().uuidString)",
                   "FREECELL_DEFAULTS_SUITE": "uitest-reset-suite-\(UUID().uuidString)"]
        let url = try #require(SaveLocation.url(environment: env))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        let suite = try #require(UserDefaults(suiteName: env["FREECELL_DEFAULTS_SUITE"]!))
        suite.set(true, forKey: AppSettings.hardCoreKey)
        SaveLocation.resetForTests(environment: env)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(UserDefaults(suiteName: env["FREECELL_DEFAULTS_SUITE"]!)?.object(forKey: AppSettings.hardCoreKey) == nil)
        var withoutName = env
        withoutName["FREECELL_SAVE_FILE"] = nil                   // would resolve to game.json
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
        #expect(SaveLocation.url(environment: ["FREECELL_SAVE_FILE": "uitest-1"])?.lastPathComponent == "uitest-1.json")
        #expect(SaveLocation.url(environment: [:])?.deletingLastPathComponent().lastPathComponent == "FreeCell")
    }
}

@MainActor @Suite struct SaveTriggers {
    @Test func everyChangeSavesButTheClockOnlyEveryFiveSeconds() {
        let a = FreeCellEngine.newGame(number: 4)
        var moved = a
        moved.cells[0] = moved.tableau[0].removeLast()
        #expect(GameStore.shouldSave(from: a, to: moved), "a move")
        var t = a
        for second in 1...10 {
            let before = t
            t.elapsed = Double(second)
            #expect(GameStore.shouldSave(from: before, to: t) == (second % 5 == 0), "tick \(second)")
        }
    }

    /// Hard Core is written whenever it changes — not from a view that may be gone.
    @Test func hardCoreIsRememberedWheneverItChanges() {
        let store = makeStore()
        var remembered: [Bool] = []
        store.rememberHardCore = { remembered.append($0) }
        store.newGame(hardCore: true)
        store.newGame(hardCore: false)
        store.newGame(hardCore: false)                              // unchanged: not written again
        #expect(remembered == [true, false])
    }

    /// Quitting or backgrounding waits until the save is on disk.
    @Test func flushingWaitsUntilTheSaveIsOnDisk() {
        let url = tempSaveURL()
        let store = makeStore()
        store.saver = GameSaver(url: url)
        playAMove(store)
        for _ in 0..<3 { store.tick() }                             // 3 s: not a save on its own
        store.flushSaves()
        #expect(GameSaver.load(from: url) == store.state, "on disk when flushSaves returns")
    }

    /// The store saves after a move and after undo — what a force-quit relaunch would find.
    @Test func theStoreSavesWhatItShows() async throws {
        let url = tempSaveURL()
        let store = makeStore()
        store.saver = GameSaver(url: url)
        playAMove(store)
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state)
        playAMove(store)
        store.undo()
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state, "after undo")
        for _ in 0..<5 { store.tick() }
        await store.lastSave?.value
        #expect(GameSaver.load(from: url)?.elapsed == 5, "the fifth second is saved")
    }
}
