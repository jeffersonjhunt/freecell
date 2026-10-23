import GameKit
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Game Center (spec "Scores"): sign-in at launch through Game Center's own prompt, each win's
/// time submitted to the board for its difficulty, and the player's best and rank read back for
/// Scores. Signed out — or under tests — it does nothing.
@Observable @MainActor
final class GameCenter {
    /// Fastest wins (spec "Scores"): scored in seconds, lowest first — one board for each mix of
    /// Hard Core and Relaxed, so an easier game never ranks against a harder one.
    enum Board: String, CaseIterable, Sendable {
        case fastest = "com.oneoffendeavors.freecell.fastest"
        case fastestHardCore = "com.oneoffendeavors.freecell.fastest.hardcore"
        case fastestRelaxed = "com.oneoffendeavors.freecell.fastest.relaxed"
        case fastestRelaxedHardCore = "com.oneoffendeavors.freecell.fastest.relaxed.hardcore"

        static func of(hardCore: Bool, relaxed: Bool = false) -> Board {
            switch (relaxed, hardCore) {
            case (false, false): .fastest
            case (false, true): .fastestHardCore
            case (true, false): .fastestRelaxed
            case (true, true): .fastestRelaxedHardCore
            }
        }

        var title: String {
            switch self {
            case .fastest: "Fastest"
            case .fastestHardCore: "Fastest · Hard Core"
            case .fastestRelaxed: "Fastest · Relaxed"
            case .fastestRelaxedHardCore: "Fastest · Relaxed, Hard Core"
            }
        }
    }

    /// The player's best time on a board, in seconds, and their place on it.
    struct Standing: Equatable, Sendable {
        let seconds: Int
        let rank: Int
    }

    private(set) var isSignedIn = false
    @ObservationIgnored let isEnabled: Bool

    init(enabled: Bool) {
        isEnabled = enabled
    }

    func signIn() {
        guard isEnabled else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, _ in
            MainActor.assumeIsolated {
                if let controller { Self.present(controller) }
                self?.isSignedIn = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    func submit(seconds: Int, hardCore: Bool, relaxed: Bool = false) {
        guard isEnabled, GKLocalPlayer.local.isAuthenticated else { return }
        let board = Board.of(hardCore: hardCore, relaxed: relaxed).rawValue
        Task {
            try? await GKLeaderboard.submitScore(seconds, context: 0, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [board])
        }
    }

    func standing(on board: Board) async -> Standing? {
        guard isEnabled, GKLocalPlayer.local.isAuthenticated,
              let leaderboard = try? await GKLeaderboard.loadLeaderboards(IDs: [board.rawValue]).first,
              let (mine, _) = try? await leaderboard.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime),
              let mine else { return nil }
        return Standing(seconds: mine.score, rank: mine.rank)
    }

    /// Opens the board in Game Center (iOS 17 / macOS 14: Game Center's leaderboards).
    func show(_ board: Board) {
        guard isEnabled, GKLocalPlayer.local.isAuthenticated else { return }
        if #available(iOS 18, macOS 15, *) {
            GKAccessPoint.shared.trigger(leaderboardID: board.rawValue, playerScope: .global, timeScope: .allTime) {}
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) {}
        }
    }

    #if canImport(UIKit)
    private static func present(_ controller: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(controller, animated: true)
    }
    #else
    private static func present(_ controller: NSViewController) {
        NSApp.keyWindow?.contentViewController?.presentAsSheet(controller)
    }
    #endif
}
