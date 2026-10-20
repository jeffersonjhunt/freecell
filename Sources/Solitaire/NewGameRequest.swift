import Foundation
import SolitaireEngine

/// A new deal the player asked for (spec "New games and the draw mode"): New Game keeps the
/// current game's mode; the draw chip and the Mac's draw items name one. A game in progress is
/// asked about first — the alert in ContentView — and anything else is replaced at once.
struct NewGameRequest: Equatable {
    let drawCount: Int
    /// A different draw mode from the game it would replace.
    let switching: Bool
    /// Whether the new game is Hard Core.
    var hardCore = false
    /// Turning Hard Core on or off (the Settings switch), rather than a new game in the same mode.
    var changesHardCore = false
    /// Restart: this same deal again from the start, rather than a new one.
    var restarts = false

    static func restart(_ state: GameState) -> NewGameRequest {
        NewGameRequest(drawCount: state.drawCount, switching: false, hardCore: state.isHardCore, restarts: true)
    }

    var title: String {
        if restarts { return "Restart this game?" }
        if changesHardCore { return hardCore ? "Turn on Hard Core?" : "Turn off Hard Core?" }
        return switching ? "Switch to Draw \(drawCount)?" : "Start a new game?"
    }
    var message: String {
        if restarts {
            return "You’ll play the same deal again from the beginning. A restarted game scores 0 and doesn’t count toward your Top 10 or Game Center."
        }
        if changesHardCore && hardCore {
            return "Draw 1 gets one pass through the deck, Draw 3 gets three. This starts a new game, and the current one will be lost."
        }
        return switching || changesHardCore ? "This starts a new game, and the current one will be lost." : "This one will be lost."
    }
    var confirm: String {
        if restarts { return "Restart" }
        if changesHardCore { return hardCore ? "Start Hard Core" : "Start New Game" }
        return switching ? "Start New Game" : "New Game"
    }
    /// The small label over the card's title.
    var kicker: String {
        if restarts { return "RESTART" }
        if changesHardCore { return "HARD CORE" }
        return switching ? "DRAW \(drawCount == 3 ? 1 : 3) → DRAW \(drawCount)" : "NEW GAME"
    }
}

extension AppUI {
    /// Deals a new game — in `drawCount`, or the current game's mode — at once, unless that would
    /// lose a game in progress and the player wants to be asked (Settings ▸ Ask before ending a
    /// game); then it only asks (`pendingNewGame`), and the question card deals or not. Asking
    /// stops auto-finish, so the game cannot be won behind the question.
    /// `hardCore`: nil keeps the current game's Hard Core mode (the Settings switch passes one).
    func requestNewGame(drawCount: Int? = nil, hardCore: Bool? = nil, store: GameStore) {
        let count = GameStore.validDrawCount(drawCount ?? store.state.drawCount)
        let hard = hardCore ?? store.state.isHardCore
        guard store.isInProgress, asksBeforeEndingGame() else {
            pendingNewGame = nil
            store.newGame(drawCount: count, hardCore: hard)
            return
        }
        store.stopAutoFinish()
        pendingNewGame = NewGameRequest(drawCount: count, switching: count != store.state.drawCount,
                                        hardCore: hard, changesHardCore: hard != store.state.isHardCore)
    }

    /// Restart (spec "Restart"): deals this game again from the start — at once, unless a game in
    /// progress would be lost and the player wants to be asked, as for a new game.
    func requestRestart(store: GameStore) {
        guard store.canRestart else { return }
        guard store.isInProgress, asksBeforeEndingGame() else {
            pendingNewGame = nil
            store.restart()
            return
        }
        store.stopAutoFinish()
        pendingNewGame = .restart(store.state)
    }

    /// The question card's confirming button: does what the pending request asked.
    func confirmPending(store: GameStore) {
        guard let request = pendingNewGame else { return }
        pendingNewGame = nil
        if request.restarts {
            store.restart()
        } else {
            store.newGame(drawCount: request.drawCount, hardCore: request.hardCore)
        }
    }
}
