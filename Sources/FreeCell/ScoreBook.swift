import Foundation
import Observation
import FreeCellEngine

/// One win in the Top 10 (spec "Scores").
struct ScoreEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var elapsed: TimeInterval
    var moves: Int
    var number: Int
    var date: Date
    var hardCore: Bool
    /// A Relaxed win (spec "Relaxed"), marked RX.
    var relaxed = false

    init(id: UUID, elapsed: TimeInterval, moves: Int, number: Int, date: Date, hardCore: Bool, relaxed: Bool = false) {
        (self.id, self.elapsed, self.moves, self.number, self.date, self.hardCore, self.relaxed)
            = (id, elapsed, moves, number, date, hardCore, relaxed)
    }

    /// Entries saved before Relaxed (the first beta) are standard wins — a Top 10 must never be
    /// lost to a new field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        elapsed = try c.decode(TimeInterval.self, forKey: .elapsed)
        moves = try c.decode(Int.self, forKey: .moves)
        number = try c.decode(Int.self, forKey: .number)
        date = try c.decode(Date.self, forKey: .date)
        hardCore = try c.decode(Bool.self, forKey: .hardCore)
        relaxed = try c.decodeIfPresent(Bool.self, forKey: .relaxed) ?? false
    }
}

/// The Top 10: the ten fastest wins, every mode together (Hard Core marked HC, Relaxed RX) — the faster first; on equal
/// times, fewer moves; then the earlier win (decision 2026-10-20).
struct TopTen: Codable, Equatable, Sendable {
    static let size = 10
    var entries: [ScoreEntry] = []

    /// Adds a win; returns its place (1–10), or nil if it didn't make the list.
    mutating func add(_ entry: ScoreEntry) -> Int? {
        entries = Self.best(entries + [entry])
        return entries.firstIndex(of: entry).map { $0 + 1 }
    }

    /// Two copies (this device's and iCloud's) combined: the best ten of both, each win once.
    func merged(with other: TopTen) -> TopTen {
        TopTen(entries: Self.best(entries + other.entries))
    }

    static func best(_ entries: [ScoreEntry]) -> [ScoreEntry] {
        var seen = Set<UUID>()
        let unique = entries.filter { seen.insert($0.id).inserted }
        return Array(unique.sorted { a, b in
            if Int(a.elapsed) != Int(b.elapsed) { return a.elapsed < b.elapsed }
            if a.moves != b.moves { return a.moves < b.moves }
            return a.date < b.date
        }.prefix(size))
    }
}

/// Wins counted per device (spec "Scores"): each device keeps its own count, and the total adds
/// them up — so copies merge by taking each device's larger count, and a win is never counted twice.
struct WinTally: Codable, Equatable, Sendable {
    var byDevice: [String: Int] = [:]

    var total: Int { byDevice.values.reduce(0, +) }

    func merged(with other: WinTally) -> WinTally {
        WinTally(byDevice: byDevice.merging(other.byDevice) { max($0, $1) })
    }
}

/// The player's Top 10 and wins: kept in UserDefaults and, when iCloud is available, in iCloud's
/// key-value store, which carries them to their other devices. Copies are merged, never overwritten.
@Observable @MainActor
final class ScoreBook {
    static let key = "topTen"
    static let winsKey = "wins"
    static let deviceKey = "scoreDevice"

    private(set) var lists = TopTen()
    private(set) var wins = WinTally()
    /// The latest win recorded this session: its game number and place, for the win card's badge
    /// and the highlight in Scores.
    private(set) var latest: Latest?

    struct Latest: Equatable {
        let id: UUID
        let number: Int
        let rank: Int?
    }

    @ObservationIgnored private let local: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// This device's name in the win tally: made once, kept in UserDefaults (never synced).
    @ObservationIgnored private let device: String

    /// - Parameter cloud: iCloud's key-value store; nil keeps everything on this device (tests).
    init(local: UserDefaults, cloud: NSUbiquitousKeyValueStore?) {
        self.local = local
        self.cloud = cloud
        if let known = local.string(forKey: Self.deviceKey) {
            device = known
        } else {
            device = UUID().uuidString
            local.set(device, forKey: Self.deviceKey)
        }
        lists = Self.decode(TopTen.self, local.data(forKey: Self.key)) ?? TopTen()
        wins = Self.decode(WinTally.self, local.data(forKey: Self.winsKey)) ?? WinTally()
        if let cloud {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud,
                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mergeFromCloud() }
            }
            cloud.synchronize()
            mergeFromCloud()
        }
    }

    /// Records a won game: one more win, and its place in the Top 10 (nil if it didn't make it).
    /// A restarted game is never recorded.
    @discardableResult
    func record(_ state: GameState, date: Date = .now) -> Int? {
        guard state.isWon, !state.isRestarted else { return nil }
        let entry = ScoreEntry(id: UUID(), elapsed: state.elapsed, moves: state.moveCount, number: state.number,
                               date: date, hardCore: state.isHardCore, relaxed: state.isRelaxed)
        let rank = lists.add(entry)
        wins.byDevice[device, default: 0] += 1
        latest = Latest(id: entry.id, number: state.number, rank: rank)
        save()
        return rank
    }

    /// The place a won game took, if it made the Top 10 (nil for any other game).
    func rank(ofWin state: GameState) -> Int? {
        guard let latest, state.isWon, !state.isRestarted, latest.number == state.number else { return nil }
        return latest.rank
    }

    private func mergeFromCloud() {
        if let remote = Self.decode(TopTen.self, cloud?.data(forKey: Self.key)) {
            let combined = lists.merged(with: remote)
            if combined != lists { lists = combined }
        }
        if let remote = Self.decode(WinTally.self, cloud?.data(forKey: Self.winsKey)) {
            let combined = wins.merged(with: remote)
            if combined != wins { wins = combined }
        }
        save()
    }

    private func save() {
        for (key, data) in [(Self.key, try? JSONEncoder().encode(lists)), (Self.winsKey, try? JSONEncoder().encode(wins))] {
            guard let data else { continue }
            local.set(data, forKey: key)
            if let cloud, cloud.data(forKey: key) != data { cloud.set(data, forKey: key) }
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
