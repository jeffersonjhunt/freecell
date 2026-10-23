import Foundation
import FreeCellEngine

/// A new deal the player asked for (spec "New games"): New Game deals a random number, Choose a
/// game a chosen one, the Hard Core switch a game in the other mode, and Restart this game again.
/// A game in progress is asked about first — the question card in ContentView — and anything else
/// is replaced at once.
struct NewGameRequest: Equatable {
    /// The game to deal; nil deals a random number.
    var number: Int?
    /// Whether the new game is Hard Core.
    var hardCore = false
    /// Turning Hard Core on or off (the Settings switch), rather than a new game in the same mode.
    var changesHardCore = false
    /// Whether the new game is Relaxed.
    var relaxed = false
    /// Turning Relaxed on or off (the Settings switch).
    var changesRelaxed = false
    /// Restart: this same game again from the start, rather than a new one.
    var restarts = false

    static func restart(_ state: GameState) -> NewGameRequest {
        NewGameRequest(number: state.number, hardCore: state.isHardCore, relaxed: state.isRelaxed, restarts: true)
    }

    var title: String {
        if restarts { return "Restart this game?" }
        if changesHardCore { return hardCore ? "Turn on Hard Core?" : "Turn off Hard Core?" }
        if changesRelaxed { return relaxed ? "Turn on Relaxed?" : "Turn off Relaxed?" }
        return "Start a new game?"
    }
    var message: String {
        if restarts {
            return "You’ll play the same game again from the beginning. A restarted game doesn’t count toward your Top 10, your wins or Game Center."
        }
        if changesHardCore && hardCore {
            return "Two free cells instead of four. This starts a new game, and the current one will be lost."
        }
        if changesRelaxed && relaxed {
            return "Any stack in order moves at once. This starts a new game, and the current one will be lost."
        }
        return changesHardCore || changesRelaxed ? "This starts a new game, and the current one will be lost." : "This one will be lost."
    }
    var confirm: String {
        if restarts { return "Restart" }
        if changesHardCore { return hardCore ? "Start Hard Core" : "Start New Game" }
        if changesRelaxed { return relaxed ? "Start Relaxed" : "Start New Game" }
        return "New Game"
    }
    /// The small label over the card's title.
    var kicker: String {
        if restarts { return "RESTART" }
        if changesHardCore { return "HARD CORE" }
        if changesRelaxed { return "RELAXED" }
        return "NEW GAME"
    }
}

extension AppUI {
    /// Deals a new game — game `number`, or a random one — at once, unless that would lose a game
    /// in progress and the player wants to be asked (Settings ▸ Ask before ending a game); then it
    /// only asks (`pendingNewGame`), and the question card deals or not. Asking stops automatic
    /// plays and Finish, so the game cannot be won behind the question.
    /// `hardCore`, `relaxed`: nil keeps the current game's mode (the Settings switches pass one).
    /// `confirmed`: the player has already agreed to end the game (Choose a game's Play button).
    func requestNewGame(number: Int? = nil, hardCore: Bool? = nil, relaxed: Bool? = nil, confirmed: Bool = false,
                        store: GameStore) {
        let hard = hardCore ?? store.state.isHardCore
        let easy = relaxed ?? store.state.isRelaxed
        guard store.isInProgress, asksBeforeEndingGame(), !confirmed else {
            pendingNewGame = nil
            deal(number: number, hardCore: hard, relaxed: easy, store: store)
            return
        }
        store.stopAutoFinish()
        pendingNewGame = NewGameRequest(number: number, hardCore: hard, changesHardCore: hard != store.state.isHardCore,
                                        relaxed: easy, changesRelaxed: easy != store.state.isRelaxed)
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
            deal(number: request.number, hardCore: request.hardCore, relaxed: request.relaxed, store: store)
        }
    }

    private func deal(number: Int?, hardCore: Bool, relaxed: Bool, store: GameStore) {
        if let number {
            store.newGame(number: number, hardCore: hardCore, relaxed: relaxed)
        } else {
            store.newGame(hardCore: hardCore, relaxed: relaxed)   // the store's own number source
        }
    }
}
