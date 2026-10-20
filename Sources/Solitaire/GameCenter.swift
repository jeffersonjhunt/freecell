import GameKit
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Game Center (spec "Scores"): sign-in at launch through Game Center's own prompt, each win
/// submitted to the board for its draw mode and difficulty, and the player's best and rank read
/// back for Scores. Signed out — or under tests — it does nothing.
@Observable @MainActor
final class GameCenter {
    enum Board: String, CaseIterable, Sendable {
        case draw1 = "com.oneoffendeavors.solitaire.draw1"
        case draw3 = "com.oneoffendeavors.solitaire.draw3"
        case draw1HardCore = "com.oneoffendeavors.solitaire.draw1.hardcore"
        case draw3HardCore = "com.oneoffendeavors.solitaire.draw3.hardcore"

        static func of(drawCount: Int, hardCore: Bool) -> Board {
            switch (drawCount == 3, hardCore) {
            case (false, false): .draw1
            case (true, false): .draw3
            case (false, true): .draw1HardCore
            case (true, true): .draw3HardCore
            }
        }

        var title: String {
            switch self {
            case .draw1: "Draw 1"
            case .draw3: "Draw 3"
            case .draw1HardCore: "Draw 1 · Hard Core"
            case .draw3HardCore: "Draw 3 · Hard Core"
            }
        }
    }

    /// The player's best on a board and their place on it.
    struct Standing: Equatable, Sendable {
        let score: Int
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

    func submit(score: Int, drawCount: Int, hardCore: Bool) {
        guard isEnabled, GKLocalPlayer.local.isAuthenticated else { return }
        let board = Board.of(drawCount: drawCount, hardCore: hardCore).rawValue
        Task {
            try? await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [board])
        }
    }

    func standing(on board: Board) async -> Standing? {
        guard isEnabled, GKLocalPlayer.local.isAuthenticated,
              let leaderboard = try? await GKLeaderboard.loadLeaderboards(IDs: [board.rawValue]).first,
              let (mine, _) = try? await leaderboard.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime),
              let mine else { return nil }
        return Standing(score: mine.score, rank: mine.rank)
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
