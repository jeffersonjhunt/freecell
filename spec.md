# FreeCell for Apple platforms — build specification

Oct 20, 2026 · @Jefferson

**One Off FreeCell**: a single SwiftUI FreeCell app for macOS, iOS and iPadOS, built from One Off
Solitaire 1.1 (`jeffersonjhunt/solitaire` at `b6c5be9`) and sharing its patterns — one shared rules
engine, one adaptive board, the same app shell, card styles, dialogs, win animations, Top 10 and
Game Center, and release tooling. No network code of its own (iCloud sync and Game Center go
through the system's services), no ads, no in-app purchases, no accounts.

## Scope and platforms

One Xcode project (XcodeGen), one multiplatform app target, one shared SwiftUI codebase. Platform
differences live in a small number of `#if os(...)` branches, not in separate views.

| Item | Value |
| --- | --- |
| Targets | macOS, iOS, iPadOS (one app target, Mac as native SwiftUI, not Catalyst) |
| Minimum OS | macOS 14, iOS 17, iPadOS 17 |
| Language | Swift 6, strict concurrency, SwiftUI app lifecycle |
| Dependencies | none — Apple frameworks only (GameKit for Game Center, Metal for the Decay shader) |
| Orientations | iPhone portrait and landscape; iPad all four; Mac resizable window |
| Game | FreeCell only |
| Bundle ID | `com.oneoffendeavors.freecell`; App Store name **One Off FreeCell**; version 1.0 |

Explicitly out of scope: ads, in-app purchases, accounts of our own, analytics, crash reporting,
remote config, hints or a solver, and any network request from the app's own code. The app must
launch straight into a playable board with no splash screen, onboarding or modal.

## Game rules

Standard FreeCell: one 52-card deck, **all face up**, in **eight columns**, with **four free cells**
and **four foundations**.

**Deal.** Every game has a **number** from 1 to 1,000,000, and the number alone decides the deal,
exactly as Microsoft FreeCell numbers them — so "game 617" is the same deal here as in any other
FreeCell that uses the numbering:

- A deck in rank-major order — A♣ A♦ A♥ A♠ 2♣ … K♠, index 0 to 51 — and a generator seeded with the
  number: `state = (state × 214013 + 2531011) mod 2³¹`, each draw `state ÷ 2¹⁶` (0…32767).
- Repeat until the deck is empty: take the card at `draw mod (cards left)`, swap the last card into
  its place, and deal the taken card.
- Cards are dealt across the eight columns in turn, left to right, one row at a time: columns 1–4
  get seven cards and columns 5–8 get six.
- The published layouts of games 1 and 617 are unit tests (see "Acceptance criteria").

**Moves** — the engine allows these and nothing else:

- The last card of a column, or a card in a free cell, to a **foundation**: an ace to an empty
  foundation, otherwise the same suit one rank higher.
- The same cards to a **column**: onto a card one rank higher and the opposite colour, or into an
  empty column.
- The last card of a column to an **empty free cell**. (A card already in a free cell moves out to a
  foundation or a column, never to another cell.)
- **A run** — the last cards of a column, each one rank lower and the opposite colour of the card
  above it — moves as one, onto a column card that accepts its first card or into an empty column,
  when it is no longer than the cards the free spaces could carry one by one:
  **(empty free cells + 1) × 2^(empty columns)**, the empty columns counted *without* the
  destination. So with four empty cells a run of five moves onto a card, and with also one empty
  column, ten.
- Cards on a foundation stay there (as in Microsoft FreeCell): there is no move back down.

**Playing cards home automatically.** After every move, any card that no other card could still
need goes to its foundation on its own: an ace or a two always; any other card when both foundations
of the other colour have reached at least one rank lower (so a red 6 goes up once both black
foundations hold their 5). These automatic plays belong to the move that freed them — they cost no
moves, and one Undo takes back the move and them together. Settings ▸ Game ▸ **Play cards home
automatically**, on by default, turns this off for players who want to place every card.

**Winning.** The game is won when all four foundations hold 13 cards. There is no loss state — a
stuck game is one the player undoes, restarts or replaces. Nearly every deal can be won: of the
first million numbers only eight cannot — 11982, 146692, 186216, 455889, 495505, 512118, 517776 and
781948 (11982 is the only one of the original 32,000).

## Architecture

The engine (`Packages/FreeCellEngine`) is a value-type library with no SwiftUI import: every rule
is unit-tested without a view. `GameStore` is the only object that mutates state, and it saves after
each applied move.

## Model types

All model types are `Sendable` value types. `GameState` is the whole game: rendering, saving and
testing all read from it.

```swift
enum Suit: Int, Codable, CaseIterable, Sendable {
    case clubs, diamonds, hearts, spades          // Microsoft's deck order
    var isRed: Bool { self == .hearts || self == .diamonds }
}

struct Card: Identifiable, Hashable, Codable, Sendable {
    let suit: Suit
    let rank: Int                                  // 1...13, ace low
    var id: Int { suit.rawValue * 13 + rank - 1 }  // stable 0...51
}

enum PileID: Hashable, Codable, Sendable {
    case cell(Int)          // 0...3 (0...1 in Hard Core)
    case foundation(Int)    // 0...3
    case tableau(Int)       // 0...7
}

struct Move: Hashable, Codable, Sendable {
    let source: PileID
    let index: Int          // first card moved, within the source pile (0 for a cell)
    let destination: PileID
}

struct GameState: Codable, Sendable, Equatable {
    var cells: [Card?]          // 4, or 2 in Hard Core
    var foundations: [[Card]]   // always 4
    var tableau: [[Card]]       // always 8
    var number: Int             // the game number, 1...1_000_000
    var isHardCore: Bool        // two free cells (see "Hard Core")
    var moveCount: Int
    var elapsed: TimeInterval
    var isWon: Bool
    var undos: Int              // survives undo itself
    var isRestarted: Bool       // a replay from the start (see "Restart")
}
```

Every pile is ordered bottom to top, so `last` is the playable card and a run to move is
`pile[index...]`. There is no face-down card anywhere in FreeCell, so `Card` has no face-up flag.

## Engine and store API

The engine is a namespace of pure functions over `GameState`; no function throws for a rejected
move — it returns `nil` or `false` so the view can simply not animate.

```swift
enum FreeCellEngine {
    static func deal(number: Int) -> [[Card]]                     // Microsoft's layout
    static func newGame(number: Int, hardCore: Bool) -> GameState
    static func restart(_ state: GameState) -> GameState         // same number, marked restarted
    static func randomNumber(using: inout some RandomNumberGenerator) -> Int  // never unwinnable
    static func canMove(_ move: Move, in state: GameState) -> Bool
    static func canPickUp(from: PileID, index: Int, in state: GameState) -> Bool
    static func apply(_ move: Move, to state: inout GameState)    // the player's: counts one move
    static func applyAutomatic(_ move: Move, to state: inout GameState)  // the game's: counts none
    static func maxRun(onto destination: PileID, in state: GameState) -> Int
    static func autoDestination(for source: PileID, index: Int, in state: GameState) -> PileID?
    static func isSafeToPlayHome(_ card: Card, in state: GameState) -> Bool
    static func nextSafePlay(in state: GameState) -> Move?        // one automatic play, or nil
    static func settle(_ state: inout GameState) -> [Move]        // every automatic play
    static func canAutoFinish(_ state: GameState) -> Bool
    static func nextAutoFinishMove(in state: GameState) -> Move?
    static func isWon(_ state: GameState) -> Bool
    static let unwinnable: Set<Int>                               // the eight numbers above
}
```

**Tap-to-move** sends the tapped card (with the cards below it, if they form a run it may move) to
the first of: its foundation (a single card); a column that accepts it, scanning left to right from
the column after its own; a free cell (a single card from a column); an empty column, if the run
fits there — never for a card already alone in its column. A card in a free cell never
goes to another cell. Nothing legal: a 0.25 s wiggle and no change.

**A run counts as one move**, however many cards it carries, and so does a card sent to a cell or a
foundation; the automatic plays and the Finish steps cost none (`applyAutomatic`). The store plays
the automatic plays one at a time, 90 ms apart, as part of the move that freed them. Undo restores the board and the move count but not the
clock or the undo count, as in Solitaire.

**Finish** (auto-finish) is offered once every column is in order — each card lower than the one
above it — so every remaining card can go home without help. It plays the lowest available card to
a foundation every 90 ms. The steps cost no moves (a fast Finish never changes a game's rank),
and each is its own undo step.

**Undo** is a stack of `GameState` snapshots pushed before every change, capped at 300 and cleared on
a new deal. A won game cannot be undone. Redo is not required.

`GameStore` (`@Observable`, main actor) owns the state, the undo stack, the one-second timer (running
only while the game is started, unwon and the app active) and the pending drag. Views call its
intents — `tap(pile:index:)`, `drop(source:index:on:)`, `undo()`, `newGame()`,
`newGame(number:)`, `restart()`, `autoFinish()` — and never mutate state themselves.

## Interaction

| Input | Behaviour |
| --- | --- |
| Tap or click a card | Tap-to-move (above); nothing legal: a wiggle |
| Drag | Lift the card and the cards below it; drop on the pile nearest the dragged card's centre. A drop the rules refuse — including a run longer than the free spaces allow — springs back in 0.2 s and wiggles |
| A run too long to move | Dragged or tapped, a run refused only by the run limit says why, for 2.5 s over the bottom of the board and to VoiceOver: "Only 2 cards can move — 1 free cell, no empty column" (into an empty column: "Only 5 cards can move into an empty column — 4 free cells, no other empty column"). Any other refusal is silent: the wiggle is the answer |
| Double-click (macOS) | Same as a click |
| Hover (macOS, iPad pointer) | A 1 pt outline on the card under the pointer |

A drag starts after 8 pt of movement. Only a card that could move with everything below it can be
lifted — a card buried under an out-of-order card wiggles instead. Cards on a foundation do
nothing when tapped and cannot be dragged.

**Keyboard and menus (macOS; the shortcuts work from an iPad keyboard too):** File ▸ New Game (⌘N),
Choose Game… (⇧⌘N); Edit ▸ Undo (⌘Z); Game ▸ Finish (⌘↩), Restart Game (⌘R, with the Restart
button on). The on-screen controls never take keyboard focus. VoiceOver labels every card by rank
and suit and its place ("Queen of hearts, column 3", "Free cell 2, empty"), and reads a refused move
as "Can't move there".

Haptics on iPhone and iPad: a light impact on a move, a success notification on a win.

## Layout and visuals

The approved mockups are the design canvas "FreeCell mockups" (decided 2026-10-20). `BoardMetrics`
is built from the available size; everything else reads from it.

| Metric | Rule |
| --- | --- |
| Board width | Available width, capped at 900 pt and centred |
| Gap | 1.8 % of board width, at least 4 pt; boards under 500 pt (phones upright): 3 pt |
| Side margin | Equal to the gap; 4 pt on boards under 500 pt |
| Card width | (board width − 2 margins − 7 gaps) / 8 |
| Card height, radius | width × 1.4; width × 0.09 |
| Top row | Free cells in columns 1–4, foundations in columns 5–8. In Hard Core the third and fourth cells are drawn closed (a dim ✕) |
| Row gap | card width × 0.3, at most 16 pt |
| Column fan | card height × 0.29, squeezed together when a column would overflow; at least 0.24 × card height while it fits (the corner index stays readable), less only for the longest columns |
| Short boards | On a phone held sideways or a short Mac window the card size is capped by the height, so the top row and a column of twelve cards fit: cards come out small there (accepted from the mockups) |
| Hit targets | 44 pt on touch; cards narrower than that widen their tap area to the whole column slot |

The controls are Solitaire's: a header over the board — **TIME** and **MOVES** in Space Mono, and
the **game chip** "#24301" (with "· HC" in Hard Core), a button that opens Choose a game — and a bar
of labelled 60 pt buttons: **Undo**, **Restart** (only with the setting on), **Finish** (burnt orange
when offered), **New Game**, **More**. On a phone held sideways the header folds into the bar
(52 pt buttons). There is no score in the header: FreeCell wins rank by time (see "Scores").

Cards are drawn in SwiftUI in the chosen face and back (see "Card styles"). The table is the dark
green gradient; faces never invert in dark mode. Moves animate with a 0.2 s ease-out; a run moves
as one piece; the automatic plays follow one by one, 90 ms apart. All motion is skipped with Reduce
Motion on.

## Colours and dialogs

Solitaire's, unchanged: burnt orange #CC5500 as the one accent (fills carry #0A0A0A text; orange text
#B04800 on light, #FF8A3D on dark); questions and the win card are dark cards (#141414, hairline
#2A2A2A, 24–28 pt corners) over the table dimmed by a 60 % black scrim; main button orange, others
outlined; Return chooses the main button, Esc cancels; VoiceOver starts at the title. On iPhone
they rise from the bottom; elsewhere they are centred, at most 480 pt wide.

- **Win card:** kicker **GAME 24301** (· HARD CORE), "You won!", **TIME** large in Space Mono,
  "IN 96 MOVES" under it, the **New Top 10 · #2** badge when the win made the list, then UNDOS,
  FREE CELLS and WINS, and the buttons **New Game** (orange), **Choose a game**, **Top 10** and
  **Close**.
- **Choose a game:** kicker NEW GAME, "Choose a game", a line on Microsoft's numbering, a numeric
  **GAME NUMBER** field (1 to 1,000,000; anything else disables Play), the note "Game 11982 is the
  one game of the first 32,000 that can't be won", and **Play Game n** (orange), **Random game** and
  **Cancel**. Opened mid-game it adds "The game in progress will end", and Play is the
  confirmation — no second question.
- **Question cards** (new game, Hard Core, restart): as in Solitaire.

## Card styles

Solitaire's four faces (Classic, Big Index, Vintage, Night) and four backs (Classic Blue, Burnt
Orange, Racing Green, Art Deco), unchanged, with the same rules: the corner index reads inside the
narrowest fan; red and black differ in lightness; no inversion in dark mode; changes apply live.
Backs appear only in the Settings preview and the Shuffle win animation.

## Scores: your Top 10 and Game Center

Only **wins** count, and only wins of a game that was not restarted. **Wins rank by time — the
faster first; on equal times, fewer moves; then the earlier win** (decision 2026-10-20).

- **Your Top 10** — one list of the ten fastest wins (every mode together, Hard Core marked **HC**
  and Relaxed **RX**), each with its time, moves, game number and date. Kept on the device and synced
  through iCloud's key-value store, merged as in Solitaire (the best ten of both copies).
- **Wins** — how many games have been won, counted per device and added up across the player's
  devices through the same iCloud store (each device keeps its own count, so a merge never counts
  a win twice).
- **Game Center** — four leaderboards in one set "FreeCell", one per mix of Hard Core and Relaxed:
  `com.oneoffendeavors.freecell.fastest`, `.fastest.hardcore`, `.fastest.relaxed` and
  `.fastest.relaxed.hardcore`, scored in seconds, lowest first, each player's best kept, shown as
  a time. Created by `tools/asc.py gamecenter`.

**Scores** (a tile on the More card) shows Your Top 10, the wins count, and the two Game Center
boards with the player's best and rank. Tests never touch the player's Top 10, iCloud or Game
Center.

## Win animations

Solitaire's four, from the foundations: **Cascade** (default), **Rainfall**, **Decay** (the Metal
dissolve), **Shuffle**, plus **Random** and **None**; Reduce Motion or None shows the win card at
once. **Shuffle** ends with the face-down deck gathered in the middle of the table (there is no draw
pile in FreeCell), where it stays until the next game.

## Hard Core

**Two free cells instead of four** (option A of the mockups, decided 2026-10-20). It is a property
of the deal, saved with the game. Fewer deals can be won with two cells; that is the challenge.

- The **Hard Core** switch in Settings ▸ Game shows the current game's mode; changing it deals a
  new game — asked first mid-game ("Turn on Hard Core?", **Start Hard Core** / **Cancel**) unless
  Ask before ending a game is off. New Game, Choose a game and the win card keep the current mode.
- On the table the third and fourth cells are closed (✕); the chip reads **#24301 · HC** (VoiceOver:
  "Game 24301, Hard Core"); the win card's kicker **GAME 24301 · HARD CORE**.
- Hard Core wins share Your Top 10, marked HC, and have their own Game Center leaderboard.
- A save whose cell count doesn't match its mode is damaged and is not resumed.

## Relaxed

**Any stack in order moves at once**, however many free cells and empty columns there are — the
run limit is lifted and every other rule stays (decision 2026-10-22, from TestFlight feedback). Like
Hard Core it is a property of the deal, saved with the game (a save without it is a standard game),
and the two mix.

- The **Relaxed** switch in Settings ▸ Game, under Hard Core, shows the current game's mode;
  changing it deals a new game, asked first mid-game ("Turn on Relaxed?", label RELAXED; **Start
  Relaxed** / **Cancel**) unless Ask before ending a game is off.
- The chip reads **#24301 · RX** (with Hard Core **#24301 · HC · RX**; VoiceOver "Game 24301,
  Relaxed"); the win card's kicker **GAME 24301 · RELAXED**.
- Relaxed wins share the Top 10, marked **RX**, and have their own Game Center boards (see
  "Scores"), so an easier game never ranks against a harder one.

## Settings, About and the More menu

**More** opens Solitaire's dark card of tiles: **How to Play**, **Scores**, **Settings**, **About**.

**Settings:**

- **Game:** Resume game at launch (on); **Hard Core** (off); **Relaxed** (off); **Play cards home automatically** (on);
  **Ask before ending a game** (on); **Restart button** (off).
- **Win animation:** the picker, as in Solitaire.
- **Card face** and **Card back:** the previews, as in Solitaire, with the live preview at the top.

**About:** the icon, **FreeCell**, **Version 1.0 (build)**; "FreeCell, made by One Off Endeavors. No
ads, no tracking, nothing to sign up for. Your Top 10 syncs through your own iCloud, and your wins
go to Game Center when you're signed in."; links **One Off Endeavors**, **Privacy policy**
(https://oneoffendeavors.com/freecell/privacy/) and **Support and feedback**
(https://oneoffendeavors.com/freecell/support/); the Space Mono acknowledgement; **© 2026 One Off
Endeavors**.

## New games

A game is **in progress** once a move has been made and it is not won; only a game in progress is
asked about, and not at all with Ask before ending a game off.

- **New Game** (the bar, ⌘N) deals a **random game number** at once — never one of the eight that
  can't be won. In progress it first asks "Start a new game? This one will be lost."
- **Choose a game** (the header chip, the win card, ⇧⌘N) opens the number card (see "Colours and
  dialogs"); any number may be typed, 11982 included.
- **The win card** offers New Game and Choose a game; nothing is asked, the game being over.

The last deal's Hard Core mode is used for the next New Game and the next launch's fresh deal.
Asking stops auto-finish where it is; Cancel leaves the game and its clock untouched.

## Restart

As in Solitaire: Settings ▸ Game ▸ **Restart button**, off by default, adds **Restart** after Undo
(and Game ▸ Restart Game, ⌘R). It deals **this game number again from the start** — moves, time and
undos back to none, undo cleared — at any point, a won game included; disabled before the first
move; asked first mid-game ("Restart this game?"). A restarted game is marked (`isRestarted`, saved
with it): its win goes to neither the Top 10, the wins count nor Game Center, and gets no badge.
Choosing a number already played — from Choose a game — is a new game, not a restart, and counts.

## Persistence and settings

The game in progress is saved as JSON to `Application Support/FreeCell/game.json`, atomically,
after every move, every fifth timer tick and when the app leaves the foreground. At launch it is
resumed only if it holds 52 distinct cards, 8 columns, 4 foundations, a cell count matching its mode
and a number in range, and isn't won; anything else is discarded silently for a fresh deal. Undo
is not saved.

Settings in `UserDefaults` (`@AppStorage`): resume, Hard Core of the last deal, play cards home
automatically, ask before ending a game, restart button, card face, card back, win animation. An
unknown stored value falls back to its default. Closing the Mac's game window quits the app.

## Acceptance criteria

Build the engine and its tests before any view.

- [ ] Games 1 and 617 deal exactly the published layouts; every deal has 52 distinct cards, columns
      of 7, 7, 7, 7, 6, 6, 6, 6, and empty cells and foundations.
- [ ] Every legal move in "Game rules" succeeds and every other is refused (unit tests on `canMove`),
      including runs one card longer than the formula allows, onto a card and into an empty column.
- [ ] Automatic plays send home exactly the cards the rule names, are one undo with their move, and
      stay off when the setting is off.
- [ ] Undo from any point returns the exact previous board and move count over 100 random moves
      from a fixed game, with the undo count rising by one each time.
- [ ] A game played to a win sets `isWon` and shows the win card with its time and moves; Finish is
      offered exactly when every column is in order.
- [ ] Hard Core deals have two cells; a move to a closed cell is refused; the run limit uses two.
- [ ] Wins rank by time, then moves, then date; a restarted game's win is recorded nowhere.
- [ ] Force-quitting mid-game and relaunching restores the board, the number, moves and time.
- [ ] The board lays out without clipping on iPhone SE upright, a Pro Max held sideways, iPad split
      view at one third, and a 600 pt wide Mac window — with a 19-card column.
- [ ] No third-party packages; the app's own code makes no network calls.

## Decisions

Each overrides anything above it conflicts with. Solitaire's decisions that still apply here are
restated, not referenced.

| Date | Decision |
| --- | --- |
| 2026-10-20 | One Off FreeCell is a copy of One Off Solitaire 1.1, not a shared package; bundle ID `com.oneoffendeavors.freecell`; public repo `jeffersonjhunt/freecell`; full feature parity in 1.0. |
| 2026-10-20 | Scoring: no points — wins rank by time, then moves (fewer first), then date; Game Center ranks fastest time. |
| 2026-10-20 | Game numbers: Microsoft's numbering, 1 to 1,000,000, shown in the header chip and typeable in Choose a game; New Game's random numbers skip the eight unwinnable ones. |
| 2026-10-20 | Hard Core: option A — one switch, two free cells; one Top 10 (HC marked), its own Game Center board. |
| 2026-10-20 | Restart kept, as in Solitaire: a restart scores nothing; choosing a number again is a new game and counts. |
| 2026-10-20 | From the mockups: free cells left, foundations right; small cards accepted on a phone held sideways; New Game random at once, the chip and the win card open Choose a game; win card leads with time. |
| 2026-10-22 | From TestFlight feedback ("rules or bug": a 6-card and a 5-card run refused with one free cell): the run limit stays, and the board now says why a run won't move; a **Relaxed** setting lifts the limit, with RX in the Top 10 and its own Game Center boards (four in all). |
| 2026-10-20 | Rules calls made for the spec (open to change): no moves back from a foundation (Microsoft's rule); safe automatic plays on by default, with a setting; a run counts as one move, and automatic plays and Finish steps as none; Finish when every column is in order; Shuffle's deck ends in the middle of the table. |
| 2026-09-27 | (From Solitaire) A won game cannot be changed or undone. Release builds can't be attached to by a debugger (`tools/check-release.sh`). Cards narrower than 44 pt widen their tap area to the column slot. |
| 2026-10-01 | (From Solitaire) One layout everywhere, the header over the board and the labelled bar along the bottom; Space Mono figures; burnt orange accent; card faces and backs as listed; About links open in the browser. Closing the Mac's game window quits. |
