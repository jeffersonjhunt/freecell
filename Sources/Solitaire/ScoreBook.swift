import Foundation
import Observation
import SolitaireEngine

/// One win in a Top 10 (spec "Scores").
struct ScoreEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var score: Int
    var elapsed: TimeInterval
    var date: Date
    var hardCore: Bool
}

/// The two Top 10 lists, Draw 1 and Draw 3: the ten best wins in each, the higher score first and,
/// on a tie, the earlier win.
struct TopTen: Codable, Equatable, Sendable {
    static let size = 10
    var draw1: [ScoreEntry] = []
    var draw3: [ScoreEntry] = []

    func list(drawCount: Int) -> [ScoreEntry] { drawCount == 3 ? draw3 : draw1 }

    /// Adds a win to its mode's list; returns its place (1–10), or nil if it didn't make the list.
    mutating func add(_ entry: ScoreEntry, drawCount: Int) -> Int? {
        if drawCount == 3 { draw3 = Self.best(draw3 + [entry]) } else { draw1 = Self.best(draw1 + [entry]) }
        return list(drawCount: drawCount).firstIndex(of: entry).map { $0 + 1 }
    }

    /// Two copies (this device's and iCloud's) combined: the best ten of both, each win once.
    func merged(with other: TopTen) -> TopTen {
        TopTen(draw1: Self.best(draw1 + other.draw1), draw3: Self.best(draw3 + other.draw3))
    }

    static func best(_ entries: [ScoreEntry]) -> [ScoreEntry] {
        var seen = Set<UUID>()
        let unique = entries.filter { seen.insert($0.id).inserted }
        return Array(unique.sorted { $0.score != $1.score ? $0.score > $1.score : $0.date < $1.date }
            .prefix(size))
    }
}

/// The player's Top 10: kept in UserDefaults and, when iCloud is available, in iCloud's key-value
/// store, which carries it to their other devices. Copies are merged, never overwritten.
@Observable @MainActor
final class ScoreBook {
    static let key = "topTen"

    private(set) var lists = TopTen()
    /// The latest win recorded this session: its game (by seed), mode and place, for the win
    /// card's badge and the highlight in Scores.
    private(set) var latest: Latest?

    struct Latest: Equatable {
        let id: UUID
        let seed: UInt64
        let drawCount: Int
        let rank: Int?
    }

    @ObservationIgnored private let local: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// - Parameter cloud: iCloud's key-value store; nil keeps the lists on this device (tests).
    init(local: UserDefaults, cloud: NSUbiquitousKeyValueStore?) {
        self.local = local
        self.cloud = cloud
        lists = Self.decode(local.data(forKey: Self.key)) ?? TopTen()
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

    /// Records a won game; returns its place in its mode's Top 10, or nil if it didn't make it.
    @discardableResult
    func record(_ state: GameState, date: Date = .now) -> Int? {
        guard state.isWon, !state.isRestarted else { return nil }   // a replay never counts
        let entry = ScoreEntry(id: UUID(), score: SolitaireEngine.score(state), elapsed: state.elapsed,
                               date: date, hardCore: state.isHardCore)
        let rank = lists.add(entry, drawCount: state.drawCount)
        latest = Latest(id: entry.id, seed: state.seed, drawCount: state.drawCount, rank: rank)
        save()
        return rank
    }

    /// The place a won game took, if it made the Top 10 (nil for any other game).
    func rank(ofWin state: GameState) -> Int? {
        guard let latest, state.isWon, !state.isRestarted, latest.seed == state.seed else { return nil }
        return latest.rank
    }

    private func mergeFromCloud() {
        guard let remote = Self.decode(cloud?.data(forKey: Self.key)) else { save(); return }
        let combined = lists.merged(with: remote)
        if combined != lists { lists = combined }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        local.set(data, forKey: Self.key)
        if let cloud, cloud.data(forKey: Self.key) != data { cloud.set(data, forKey: Self.key) }
    }

    private static func decode(_ data: Data?) -> TopTen? {
        data.flatMap { try? JSONDecoder().decode(TopTen.self, from: $0) }
    }
}
