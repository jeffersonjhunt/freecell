import Foundation
import Testing
import FreeCellEngine
@testable import FreeCell

/// Spec "Scores": the Top 10 by time, how copies merge, the wins tally, recording wins, and the
/// Game Center boards.
@Suite struct TopTenLists {
    func entry(_ seconds: TimeInterval, moves: Int = 90, minutesAgo: Double = 0, hardCore: Bool = false) -> ScoreEntry {
        ScoreEntry(id: UUID(), elapsed: seconds, moves: moves, number: 617,
                   date: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), hardCore: hardCore)
    }

    /// The faster first; on equal times fewer moves; then the earlier win; and only ten.
    @Test func fastestFirstThenFewerMovesThenEarlierAndOnlyTen() {
        var t = TopTen()
        let slowMoves = entry(200, moves: 120), fewMoves = entry(200, moves: 80)
        let older = entry(300, minutesAgo: 10), newer = entry(300)
        #expect(t.add(slowMoves) == 1)
        #expect(t.add(fewMoves) == 1, "the same time in fewer moves ranks higher")
        #expect(t.add(newer) == 3)
        #expect(t.add(older) == 3, "a full tie goes to the earlier win")
        for s in [100.0, 900, 400, 500, 600, 700] { _ = t.add(entry(s)) }
        #expect(t.entries.count == 10)
        #expect(t.add(entry(950)) == nil, "slower than the tenth: not listed")
        #expect(t.entries.map(\.elapsed) == [100, 200, 200, 300, 300, 400, 500, 600, 700, 900])
        #expect(t.entries[1].moves == 80 && t.entries[3].id == older.id)
    }

    /// Times compare by whole seconds, as shown: 3:20.4 and 3:20.9 are a tie, then moves decide.
    @Test func timesCompareAsShown() {
        var t = TopTen()
        _ = t.add(entry(200.4, moves: 100))
        #expect(t.add(entry(200.9, moves: 90)) == 1)
    }

    @Test func copiesMergeIntoTheBestTenOfBoth() {
        var phone = TopTen(), mac = TopTen()
        let shared = entry(150)
        _ = phone.add(shared)
        _ = mac.add(shared)
        for s in 1...6 { _ = phone.add(entry(Double(200 + 10 * s))); _ = mac.add(entry(Double(205 + 10 * s))) }
        let both = phone.merged(with: mac)
        #expect(both.entries.count == 10)
        #expect(both.entries.filter { $0.id == shared.id }.count == 1, "each win once")
        #expect(both.entries.first?.id == shared.id && both.entries.map(\.elapsed) == both.entries.map(\.elapsed).sorted())
        #expect(both == mac.merged(with: phone), "the same either way round")
    }
}

@Suite struct Wins {
    /// Each device counts its own wins; the total adds them up, and merging never counts twice.
    @Test func devicesAddUpAndMergingNeverCountsTwice() {
        let phone = WinTally(byDevice: ["phone": 5, "mac": 2])
        let mac = WinTally(byDevice: ["phone": 4, "mac": 3])
        let both = phone.merged(with: mac)
        #expect(both.byDevice == ["phone": 5, "mac": 3] && both.total == 8)
        #expect(both.merged(with: both) == both, "merging again changes nothing")
        #expect(both == mac.merged(with: phone))
    }
}

@MainActor @Suite struct RecordingWins {
    func wonState(number: Int = 42, hardCore: Bool = false, seconds: TimeInterval = 90) -> GameState {
        var s = FreeCellEngine.newGame(number: number, hardCore: hardCore)
        s.foundations = Suit.allCases.map { suit in (1...13).map { Card(suit: suit, rank: $0) } }
        s.tableau = Array(repeating: [], count: 8)
        s.isWon = true; s.elapsed = seconds; s.moveCount = 88
        return s
    }

    func suite() throws -> (UserDefaults, String) {
        let name = "scores-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func aWinIsRecordedKeptRankedAndCounted() throws {
        let (d, name) = try suite()
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        let won = wonState(number: 617, hardCore: true)
        #expect(book.record(won) == 1)
        let first = try #require(book.lists.entries.first)
        #expect(first.elapsed == 90 && first.moves == 88 && first.number == 617 && first.hardCore)
        #expect(book.wins.total == 1)
        #expect(book.rank(ofWin: won) == 1, "the win card's badge")
        #expect(book.rank(ofWin: wonState(number: 7)) == nil, "only for that game")
        #expect(book.record(wonState(number: 8, seconds: 60)) == 1, "faster goes to the top")
        #expect(book.wins.total == 2)
        let again = ScoreBook(local: d, cloud: nil)
        #expect(again.lists == book.lists && again.wins == book.wins, "kept on the device")
    }

    @Test func onlyWinsAreRecorded() throws {
        let (d, name) = try suite()
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        #expect(book.record(FreeCellEngine.newGame(number: 1)) == nil)
        #expect(book.lists == TopTen() && book.wins.total == 0)
    }

    /// The store reports a win once, as the winning move lands.
    @Test func theStoreReportsAWinOnce() {
        var s = wonState()
        let king = s.foundations[3].removeLast()
        s.isWon = false
        s.tableau[0] = [king]
        let store = makeStore(at: s)
        var wins: [GameState] = []
        store.onWin = { wins.append($0) }
        #expect(store.tap(pile: .tableau(0), index: 0))
        #expect(wins.count == 1 && wins[0].isWon)
    }

    /// A restarted game's win counts nowhere (spec "Restart"): the store doesn't report it, the
    /// Top 10 and the wins don't take it, and it gets no badge even when its first playing made
    /// the list.
    @Test func aRestartedWinCountsNowhere() throws {
        let (d, name) = try suite()
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        #expect(book.record(wonState()) == 1, "the first playing of game 42")
        var replay = wonState()
        replay.isRestarted = true
        #expect(book.record(replay) == nil && book.lists.entries.count == 1 && book.wins.total == 1)
        #expect(book.rank(ofWin: replay) == nil)

        let king = replay.foundations[3].removeLast()
        replay.isWon = false
        replay.tableau[0] = [king]
        let store = makeStore(at: replay)
        var wins: [GameState] = []
        store.onWin = { wins.append($0) }
        #expect(store.tap(pile: .tableau(0), index: 0) && store.state.isWon)
        #expect(wins.isEmpty)
    }

    /// Tests never reach iCloud or Game Center.
    @Test func testsStayOffOutsideServices() {
        #expect(!AppSettings.usesOutsideServices)
    }
}

@Suite struct GameCenterBoards {
    /// One board per mix of Hard Core and Relaxed, so an easier game never ranks against a harder one.
    @Test func fastestTimeForEachMode() {
        #expect(GameCenter.Board.of(hardCore: false).rawValue == "com.oneoffendeavors.freecell.fastest")
        #expect(GameCenter.Board.of(hardCore: true).rawValue == "com.oneoffendeavors.freecell.fastest.hardcore")
        #expect(GameCenter.Board.of(hardCore: false, relaxed: true).rawValue == "com.oneoffendeavors.freecell.fastest.relaxed")
        #expect(GameCenter.Board.of(hardCore: true, relaxed: true).rawValue == "com.oneoffendeavors.freecell.fastest.relaxed.hardcore")
        #expect(Set(GameCenter.Board.allCases.map(\.rawValue)).count == 4)
    }

    /// A Relaxed win goes in the Top 10 marked RX; a Top 10 saved before Relaxed still loads.
    @MainActor @Test func relaxedWinsAreMarkedAndOldListsStillLoad() throws {
        let name = "scores-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let book = ScoreBook(local: d, cloud: nil)
        var s = FreeCellEngine.newGame(number: 3, relaxed: true)
        s.foundations = Suit.allCases.map { suit in (1...13).map { Card(suit: suit, rank: $0) } }
        s.tableau = Array(repeating: [], count: 8); s.isWon = true; s.elapsed = 70
        #expect(book.record(s) == 1 && book.lists.entries.first?.relaxed == true)
        let old = #"{"entries":[{"id":"5D6B2D84-6C4E-4F0B-9A55-1F1A3C0C5E21","elapsed":120,"moves":80,"number":617,"date":0,"hardCore":false}]}"#
        let decoded = try JSONDecoder().decode(TopTen.self, from: Data(old.utf8))
        #expect(decoded.entries.count == 1 && !decoded.entries[0].relaxed, "an entry from the first beta")
    }

    @MainActor @Test func switchedOffItDoesNothing() async {
        let gc = GameCenter(enabled: false)
        gc.signIn()
        gc.submit(seconds: 200, hardCore: false)
        #expect(!gc.isSignedIn)
        #expect(await gc.standing(on: .fastest) == nil)
    }
}

@Suite struct ScoreDates {
    @Test func todayOrAShortDate() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(ScoresView.day(now, now: now) == "Today")
        #expect(ScoresView.day(now.addingTimeInterval(-86_400 * 3), now: now) != "Today")
    }
}
