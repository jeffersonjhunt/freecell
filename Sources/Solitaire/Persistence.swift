import Foundation
import SolitaireEngine

/// Writes the game in progress as JSON, atomically, off the main actor (spec: "Persistence and
/// settings"). Each save carries a sequence number, so a save that arrives late can never
/// overwrite a newer one. Nothing is written anywhere but this one local file.
actor GameSaver {
    let url: URL
    private var lastWritten = -1

    init(url: URL) {
        self.url = url
    }

    /// Saves `state` unless a newer save (higher `sequence`) has already been written.
    func save(_ state: GameState, sequence: Int) throws {
        guard sequence > lastWritten else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(SaveFile(game: state, savedAt: Date()))
        try data.write(to: url, options: .atomic)
        lastWritten = sequence
    }

    /// The saved game, if there is one that decodes, has a known format version and passes
    /// `SaveValidation`; nil otherwise.
    nonisolated static func load(from url: URL) -> GameState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(SaveFile.self, from: data),
              file.version == SaveFile.currentVersion,
              SaveValidation.isResumable(file.game) else { return nil }
        return file.game
    }
}

/// The file format: the game inside a small envelope, so the format can evolve (`version`) and two
/// copies can be ordered (`savedAt`) — what an iCloud sync would need later (spec: the save format
/// must not block it).
struct SaveFile: Codable, Equatable {
    static let currentVersion = 1
    var version = SaveFile.currentVersion
    var savedAt: Date
    var game: GameState

    init(game: GameState, savedAt: Date) {
        self.game = game
        self.savedAt = savedAt
    }
}

/// Whether a decoded save is a game we can resume: 52 distinct real cards in 4 foundations and 7
/// columns, a valid draw mode, sane counters, not already won (spec + decision F6) — and piles
/// shaped the way play leaves them, so a damaged file can never restore a stuck game: stock face
/// down, waste face up, each foundation one suit ascending from the ace, each column face-down
/// cards under a face-up built run with a face-up last card. Anything else is discarded silently
/// and a fresh game dealt.
enum SaveValidation {
    static func isResumable(_ s: GameState) -> Bool {
        guard s.foundations.count == 4, s.tableau.count == 7,
              s.drawCount == 1 || s.drawCount == 3,
              !s.isWon, !SolitaireEngine.isWon(s),
              s.moveCount >= 0, s.elapsed >= 0, s.elapsed.isFinite,
              (0...s.moveCount).contains(s.redeals),            // each redeal is itself a move
              s.undos >= 0,
              s.passes <= s.maxPasses ?? .max                   // Hard Core: within its limit
        else { return false }
        let cards = s.stock + s.waste + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
        guard cards.count == 52, cards.allSatisfy({ (1...13).contains($0.rank) }),
              Set(cards.map(\.id)).count == 52 else { return false }
        guard s.stock.allSatisfy({ !$0.isFaceUp }), s.waste.allSatisfy(\.isFaceUp) else { return false }
        for f in s.foundations {
            for (i, card) in f.enumerated() where !card.isFaceUp || card.rank != i + 1 || card.suit != f[0].suit {
                return false
            }
        }
        for column in s.tableau where !column.isEmpty {
            guard let firstUp = column.firstIndex(where: \.isFaceUp),
                  column[firstUp...].allSatisfy(\.isFaceUp) else { return false }   // last card face up
            let run = column[firstUp...]
            for (lower, upper) in zip(run, run.dropFirst())
            where upper.rank != lower.rank - 1 || upper.suit.isRed == lower.suit.isRed {
                return false
            }
        }
        return true
    }
}

/// What to do at launch: resume the saved game (when the player wants that and it is valid) or
/// deal a fresh one in the remembered draw mode.
enum LaunchPlan: Equatable {
    case resume(GameState)
    case deal(drawCount: Int, hardCore: Bool = false)

    static func decide(saved: GameState?, resumePreferred: Bool, drawCount: Int,
                       hardCore: Bool = false) -> LaunchPlan {
        if resumePreferred, let saved { return .resume(saved) }
        return .deal(drawCount: GameStore.validDrawCount(drawCount), hardCore: hardCore)
    }
}

/// Where the game is saved: Application Support/Solitaire/game.json. Debug builds let tests use
/// their own file (SOLITAIRE_SAVE_FILE), and the unit-test host never persists: on the Mac it
/// shares the real app's sandbox container, so it would otherwise read and overwrite the player's
/// real game.
enum SaveLocation {
    /// Debug builds only: forget a UI test's own save and settings before it starts
    /// (SOLITAIRE_RESET=1), so repeated test runs reuse one file instead of piling up new ones.
    static func resetForTests(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        guard environment["SOLITAIRE_RESET"] == "1", let url = url(environment: environment),
              url.lastPathComponent != "game.json" else { return }       // never the player's game
        try? FileManager.default.removeItem(at: url)
        if let suite = environment["SOLITAIRE_DEFAULTS_SUITE"] {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        #endif
    }

    static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil { return nil }        // unit-test host
        let name = environment["SOLITAIRE_SAVE_FILE"] ?? "game"
        #else
        let name = "game"
        #endif
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("Solitaire", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }
}
