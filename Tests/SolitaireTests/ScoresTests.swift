import Foundation
import Testing
import SolitaireEngine
@testable import Solitaire

/// Spec "Scores": the two Top 10 lists, how copies merge, recording wins, and the Game Center boards.
@Suite struct TopTenLists {
    func entry(_ score: Int, minutesAgo: Double = 0, hardCore: Bool = false) -> ScoreEntry {
        ScoreEntry(id: UUID(), score: score, elapsed: 200, date: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60),
                   hardCore: hardCore)
    }

    @Test func bestFirstTheEarlierWinOnATieAndOnlyTen() {
        var t = TopTen()
        let older = entry(500, minutesAgo: 10), newer = entry(500)
        #expect(t.add(newer, drawCount: 1) == 1)
        #expect(t.add(older, drawCount: 1) == 1, "a tie goes to the earlier win")
        for s in [900, 100, 300, 700, 650, 640, 630, 620] { _ = t.add(entry(s), drawCount: 1) }
        #expect(t.draw1.count == 10)
        #expect(t.add(entry(50), drawCount: 1) == nil, "below the tenth: not listed")
        #expect(t.draw1.map(\.score) == [900, 700, 650, 640, 630, 620, 500, 500, 300, 100])
        #expect(t.draw3.isEmpty, "Draw 3 has its own list")
    }

    @Test func copiesMergeIntoTheBestTenOfBoth() {
        var phone = TopTen(), mac = TopTen()
        let shared = entry(800)
        _ = phone.add(shared, drawCount: 3)
        _ = mac.add(shared, drawCount: 3)
        for s in 1...6 { _ = phone.add(entry(100 * s), drawCount: 3); _ = mac.add(entry(100 * s + 50), drawCount: 3) }
        let both = phone.merged(with: mac)
        #expect(both.draw3.count == 10)
        #expect(both.draw3.filter { $0.id == shared.id }.count == 1, "each win once")
        #expect(both.draw3.first?.score == 800 && both.draw3.map(\.score) == both.draw3.map(\.score).sorted(by: >))
        #expect(both == mac.merged(with: phone), "the same either way round")
    }
}

@MainActor @Suite struct RecordingWins {
    func wonState(drawCount: Int = 1, hardCore: Bool = false, seed: UInt64 = 42) -> GameState {
        var s = SolitaireEngine.newGame(drawCount: drawCount, seed: seed, hardCore: hardCore)
        s.foundations = Suit.allCases.map { suit in (1...13).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
        s.tableau = Array(repeating: [], count: 7); s.stock = []; s.waste = []
        s.isWon = true; s.elapsed = 90
        return s
    }

    func suite() throws -> (UserDefaults, String) {
        let name = "scores-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func aWinIsRecordedKeptAndRanked() throws {
        let (d, name) = try suite()
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        let won = wonState(drawCount: 3, hardCore: true)
        #expect(book.record(won) == 1)
        #expect(book.lists.draw3.first?.score == SolitaireEngine.score(won) && book.lists.draw3.first?.hardCore == true)
        #expect(book.rank(ofWin: won) == 1, "the win card's badge")
        #expect(book.rank(ofWin: wonState(seed: 7)) == nil, "only for that game")
        let again = ScoreBook(local: d, cloud: nil)
        #expect(again.lists == book.lists, "kept on the device")
    }

    @Test func onlyWinsAreRecorded() throws {
        let (d, name) = try suite()
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        #expect(book.record(SolitaireEngine.newGame(drawCount: 1, seed: 1)) == nil)
        #expect(book.lists == TopTen())
    }

    /// The store reports a win once, as the winning move lands.
    @Test func theStoreReportsAWinOnce() {
        let store = makeStore()
        var s = wonState()
        let king = s.foundations[3].removeLast()
        s.isWon = false
        s.tableau[0] = [king]
        store.resume(from: s)
        var wins: [GameState] = []
        store.onWin = { wins.append($0) }
        #expect(store.tap(pile: .tableau(0), index: 0))
        #expect(wins.count == 1 && wins[0].isWon)
    }

    /// A restarted game's win counts nowhere (spec "Restart"): the store doesn't report it, the
    /// Top 10 doesn't take it, and it gets no badge even when its first playing made the list.
    @Test func aRestartedWinCountsNowhere() throws {
        let (d, name) = try suite()
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        #expect(book.record(wonState()) == 1, "the first playing of seed 42")
        var replay = wonState()
        replay.isRestarted = true
        #expect(book.record(replay) == nil && book.lists.draw1.count == 1)
        #expect(book.rank(ofWin: replay) == nil)

        let store = makeStore()
        let king = replay.foundations[3].removeLast()
        replay.isWon = false
        replay.tableau[0] = [king]
        store.resume(from: replay)
        var wins: [GameState] = []
        store.onWin = { wins.append($0) }
        #expect(store.tap(pile: .tableau(0), index: 0) && store.state.isWon)
        #expect(wins.isEmpty && store.score == 0 && store.timeBonus == 0)
    }

    /// Tests never reach iCloud or Game Center.
    @Test func testsStayOffOutsideServices() {
        #expect(!AppSettings.usesOutsideServices)
    }
}

@Suite struct GameCenterBoards {
    @Test func oneBoardPerModeAndDifficulty() {
        #expect(GameCenter.Board.of(drawCount: 1, hardCore: false).rawValue == "com.oneoffendeavors.solitaire.draw1")
        #expect(GameCenter.Board.of(drawCount: 3, hardCore: false).rawValue == "com.oneoffendeavors.solitaire.draw3")
        #expect(GameCenter.Board.of(drawCount: 1, hardCore: true).rawValue == "com.oneoffendeavors.solitaire.draw1.hardcore")
        #expect(GameCenter.Board.of(drawCount: 3, hardCore: true).rawValue == "com.oneoffendeavors.solitaire.draw3.hardcore")
        #expect(Set(GameCenter.Board.allCases.map(\.rawValue)).count == 4)
    }

    @MainActor @Test func switchedOffItDoesNothing() async {
        let gc = GameCenter(enabled: false)
        gc.signIn()
        gc.submit(score: 900, drawCount: 1, hardCore: false)
        #expect(!gc.isSignedIn)
        #expect(await gc.standing(on: .draw1) == nil)
    }
}

@Suite struct ScoreDates {
    @Test func todayOrAShortDate() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(ScoresView.day(now, now: now) == "Today")
        #expect(ScoresView.day(now.addingTimeInterval(-86_400 * 3), now: now) != "Today")
    }
}
