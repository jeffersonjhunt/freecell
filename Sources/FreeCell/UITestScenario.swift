#if DEBUG
import Foundation
import FreeCellEngine

/// Debug-only environment variables so UI tests start from a known position:
///   FREECELL_GAME=<n>          deal game number n (and New Game deals n + 1, n + 2, …)
///   FREECELL_SCENARIO=<name>   a prepared position (see `state(named:)`)
///
/// Environment, not launch arguments: macOS treats unrecognised command-line arguments as files
/// to open, and an app launched to "open" a file skips its initial window — the UI-test launches
/// came up with a menu bar and no board.
enum UITestScenario {
    @MainActor
    static func storeFromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> GameStore? {
        let number = environment["FREECELL_GAME"].flatMap(Int.init).map { min(max($0, 1), 1_000_000) }
        let scenario = environment["FREECELL_SCENARIO"].flatMap(state(named:))
        guard number != nil || scenario != nil else { return nil }
        var next = number ?? 4
        let store = GameStore {
            defer { next = next % 1_000_000 + 1 }
            return next
        }
        if let scenario { store.resume(from: scenario) }
        return store
    }

    /// - `almostWon`: ace to ten of every suit on the foundations; the J, Q, K of each suit in four
    ///   columns, the other four empty — every column is in order, so Finish is offered and wins.
    /// - `kingToAce`: column 1 holds a run from K♠ down to A♠ (spades and hearts alternating),
    ///   column 2 is empty and the rest of game 4's cards fill columns 3–8 — the drag Instruments
    ///   measures (`make profile` launches this position). The whole run lifts; FreeCell's run limit
    ///   refuses the drop, so it springs back.
    static func state(named name: String) -> GameState? {
        switch name {
        case "almostWon":
            var s = FreeCellEngine.newGame(number: 1)
            s.foundations = Suit.allCases.map { suit in (1...10).map { Card(suit: suit, rank: $0) } }
            func run(_ suit: Suit) -> [Card] { (11...13).reversed().map { Card(suit: suit, rank: $0) } }
            s.tableau = Suit.allCases.map(run) + Array(repeating: [], count: 4)
            return s
        case "kingToAce":
            let run = (1...13).reversed().map { rank in Card(suit: rank % 2 == 1 ? .spades : .hearts, rank: rank) }
            let runIDs = Set(run.map(\.id))
            var s = FreeCellEngine.newGame(number: 4)
            var rest = s.tableau.flatMap { $0 }.filter { !runIDs.contains($0.id) }      // 39 cards
            s.tableau[0] = run
            s.tableau[1] = []
            for t in 2..<8 {
                let take = t < 5 ? 7 : 6                                              // 7+7+7+6+6+6
                s.tableau[t] = Array(rest.prefix(take))
                rest.removeFirst(take)
            }
            return s
        default:
            return nil
        }
    }
}
#endif
