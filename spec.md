# Solitaire for Apple platforms — build specification

Sep 27, 2026 · @Jefferson

A single SwiftUI Klondike solitaire app for macOS, iOS and iPadOS: one shared game engine, one adaptive board view, no network code of its own (1.1's iCloud sync and Game Center go through the system's services), no ads, no in-app purchases, no accounts.

## Scope and platforms

One Xcode project, one multiplatform app target, one shared SwiftUI codebase. Platform differences live in a small number of `#if os(...)` branches, not in separate views.

| Item | Value |
| --- | --- |
| Targets | macOS, iOS, iPadOS (one app target, Mac as native AppKit-backed SwiftUI, not Catalyst) |
| Minimum OS | macOS 14, iOS 17, iPadOS 17 |
| Language | Swift 6, strict concurrency, SwiftUI app lifecycle |
| Dependencies | none — Foundation, SwiftUI, Observation, and SpriteKit only if a win animation is added |
| Orientations | iPhone portrait and landscape; iPad all four; Mac resizable window |
| Game | Klondike only |

Explicitly out of scope: ads, in-app purchases, accounts of our own, sign-in to us, analytics, crash reporting, remote config, and any network request from the app's own code. The app ships with no `NSAppTransportSecurity` needs. Version 1.0 had no entitlements beyond sandbox defaults; 1.1 adds Game Center and the iCloud key-value store (see "Scores"), both reached through the system, never a connection the app opens.

The app must launch straight into a playable board with no splash screen, onboarding, or modal.

## Game rules

Standard Klondike with a 52-card deck, seven tableau columns, four foundations, one stock and one waste.

Deal: column *i* (0-based) receives *i*+1 cards; only its last card is face up. The remaining 24 cards form the stock, all face down.

Legal moves the engine must allow, and nothing else:

- Waste top card, or a tableau column's bottom-most face-up card, to a foundation: an ace onto an empty foundation, otherwise same suit and rank exactly one higher than the foundation's top card.
- A single card, or a run of face-up cards taken from any face-up position in a column, onto another column: the run's first card must be one rank lower than the destination's top card and of the opposite colour. Only a king (with the run below it) may move onto an empty column.
- Foundation top card back to a tableau column, under the same colour-and-rank rule.
- Turning a card face up: when a move leaves a column's last card face down, it flips face up automatically. This is part of the same move for undo purposes.

Draw modes: draw 1 or draw 3, fixed for the life of a deal; switching mode deals a new game (see "New games and the draw mode"). Draw 3 turns up to three cards to the waste and only the topmost is playable. Redeals are unlimited: with the stock empty, tapping it returns the waste to the stock in reverse order, face down, and counts as one move. The game counts its **passes** through the deck: the first trip through the stock is pass 1, and each redeal starts another (`redeals` in the state; passes = redeals + 1). Undo takes a redeal back with the rest of the move. A game saved before passes were counted resumes with none.

The game is won when all four foundations hold 13 cards (for its score see "Scoring"). There is no loss state — a stuck game is simply a game the player restarts or undoes out of.

## Architecture

&#91;embedded content: app architecture · 6 components\]

The engine is a value-type library with no SwiftUI import: every rule can be unit-tested without a view. The store is the only object that mutates state, and it saves after each applied move.

## Model types

All model types are `Sendable` value types in a `SolitaireEngine` folder or local Swift package. `GameState` is the whole game: rendering, saving and testing all read from it.

```swift
enum Suit: Int, Codable, CaseIterable, Sendable {
    case spades, hearts, diamonds, clubs
    var isRed: Bool { self == .hearts || self == .diamonds }
}

struct Card: Identifiable, Hashable, Codable, Sendable {
    let suit: Suit
    let rank: Int          // 1...13, ace low
    var isFaceUp: Bool
    var id: Int { suit.rawValue * 13 + rank - 1 }   // stable 0...51
}

enum PileID: Hashable, Codable, Sendable {
    case stock, waste
    case foundation(Int)   // 0...3
    case tableau(Int)      // 0...6
}

struct Move: Hashable, Codable, Sendable {
    let source: PileID
    let index: Int         // first card moved, within the source pile
    let destination: PileID
}

struct GameState: Codable, Sendable {
    var stock: [Card]      // last element is the top, drawn first
    var waste: [Card]
    var foundations: [[Card]]  // always 4
    var tableau: [[Card]]      // always 7
    var drawCount: Int         // 1 or 3
    var moveCount: Int
    var elapsed: TimeInterval
    var isWon: Bool
    var seed: UInt64           // the shuffle seed, for replay and tests
    var redeals: Int           // times the waste was turned back over (passes = redeals + 1)
    var isHardCore: Bool       // Hard Core: passes limited (see "Hard Core")
    var undos: Int             // undos taken in this game (scoring); survives undo itself
}
```

Order convention: every pile is ordered bottom to top, so `last` is the visible or playable card, and a tableau run to move is `pile[index...]`. `id` is derived from suit and rank so SwiftUI `matchedGeometryEffect` and animations track the same card across piles.

Shuffling uses a seeded generator (`SplitMix64` or similar, roughly 20 lines) rather than `shuffled()`, so a failing game can be reproduced in a test from its seed alone.

## Engine and store API

The engine is a namespace of pure functions over `GameState`. No function may throw for a rejected move — it returns `nil` or `false` so the UI can simply not animate.

```swift
enum SolitaireEngine {
    static func newGame(drawCount: Int, seed: UInt64) -> GameState
    static func canMove(_ move: Move, in state: GameState) -> Bool
    static func apply(_ move: Move, to state: inout GameState)      // precondition: canMove
    static func drawFromStock(_ state: inout GameState)             // draws, or redeals when empty
    static func autoDestination(for source: PileID, index: Int,
                                in state: GameState) -> PileID?     // tap-to-move target
    static func canAutoFinish(_ state: GameState) -> Bool
    static func nextAutoFinishMove(in state: GameState) -> Move?
    static func isWon(_ state: GameState) -> Bool
}
```

Tap-to-move picks a destination in this order: the matching foundation if a single card can go there; then a non-empty tableau column that accepts the run, scanning left to right starting after the source column; then an empty column, unless the run already sits alone at the bottom of a column, which would be a no-op shuffle.

Auto-finish is offered when the stock and waste are empty and every tableau card is face up. It plays the lowest available rank to a foundation every 90 ms until no move remains, and each step is a normal move, so undo walks back through them.

Undo is a stack of `GameState` snapshots pushed before every state change, capped at 300 entries and cleared on a new deal. Draw, redeal, move and flip are all undoable; a flip is never undone separately from the move that caused it. Redo is not required. Undo restores the board, the move count and the passes, but not the clock or the undo count: time keeps running and each undo is counted (both cost points — see "Scoring"), so undoing can never earn back time.

`GameStore` is an `@Observable final class` on the main actor. It owns the current `GameState`, the undo stack, a one-second timer that ticks only while the game is started, unwon and the app is active, and the pending drag. Views call intents on it — `tap(pile:index:)`, `drop(source:index:on:)`, `tapStock()`, `undo()`, `newGame(drawCount:)`, `autoFinish()` — and never mutate state themselves.

## Interaction

Every platform supports both ways of moving a card: a single tap or click sends it to the best legal destination, and a drag places it exactly.

| Input | Behaviour |
| --- | --- |
| Tap or click a face-up card | Move it (with the run below it) to the auto destination; if none, a 0.25 s wiggle and no state change |
| Tap or click the stock | Draw; when the stock is empty and the waste is not, redeal |
| Drag | Lift the card and its run above the board, drop on the pile whose frame the dragged card's centre is nearest; an illegal drop springs back |
| Double-click (macOS) | Same as tap — send to foundation if possible |
| Hover (macOS, iPadOS pointer) | Highlight the card under the pointer at 1 px stroke; no other hover effect |

A drag begins after 8 points of movement so a slow tap is still a tap. The dragged run renders in an overlay above all piles with a slightly stronger shadow, tracks the finger or pointer one-to-one, and animates home in 0.2 s on an illegal drop. Only face-up cards are draggable, and only the top card of the waste or a foundation.

Keyboard and menus on macOS, through `CommandGroup`: New Game (⌘N), New Game: Draw 1 / Draw 3, Undo (⌘Z), Draw (space), Auto-finish (⌘⏎), Draw Three in a Game menu (it switches mode as the draw chip does), and the standard window and help groups. On iPadOS the same shortcuts work from a hardware keyboard via `.keyboardShortcut`. Like the cards, the on-screen controls (the bar's buttons and the draw chip) never take keyboard focus, so no focus ring is drawn and Space always draws rather than pressing a focused button; the keyboard reaches every one of them through the shortcuts and menus. VoiceOver labels every card as rank and suit, and every empty pile by name.

Haptics on iOS and iPadOS only: a light impact on a successful move, a soft impact on a stock draw, a success notification on a win. Nothing on failure beyond the wiggle. Sound is out of scope for v1.

## Layout and visuals

`BoardMetrics` is a struct built from the available size in a `GeometryReader`. Everything else reads from it, so there are no magic numbers in the views.

| Metric | Rule |
| --- | --- |
| Board width | Available width, capped at 900 pt and centred |
| Gap | 1.8% of board width, minimum 4 pt; boards narrower than 500 pt (phones in portrait): 3 pt |
| Side margin | Equal to the gap; 4 pt on boards narrower than 500 pt |
| Card width | (board width − 2 side margins − 6 gaps) / 7 |
| Row gap | Space between the top row and the columns: card width × 0.8, at most 16 pt on a touch board wider than it is tall |
| Card height | Card width × 1.4 |
| Corner radius | Card width × 0.09 |
| Top row | Stock at column 0, waste at column 1, foundations at columns 3 to 6. With **Draw pile on the right** (Settings) the row is mirrored: foundations at columns 0 to 3 (foundation 1 leftmost), waste at column 5, stock at column 6. The tableau never moves. |
| Draw 3 waste fan | The top three waste cards fan into the empty column between the draw pile and the foundations, 0.3 × card width apart, so the two beneath the playable card show their corner index at their left edge. Draw pile on the left: rightwards from the waste's slot, the playable card furthest right. On the right: the playable card stays on the waste's slot beside the stock, and the two beneath it step leftwards. |
| Face-down fan | Card height × 0.12 |
| Face-up fan | Card height × 0.29, scaled down together with the face-down fan when a column would overflow the board |
| Minimum hit target | 44 pt on touch; cards below that width force a compressed layout |

The same seven-column board is used on every platform: on a Mac or iPad the cards simply get larger until the 900 pt cap, and the extra height goes to the tableau. The controls are the same everywhere too (decision 2026-10-01): a header over the board with the score, elapsed time, moves and the draw chip (the current game's draw mode, a button) in Space Mono, and a bar along the bottom with four labelled 60 pt buttons — Undo, Finish (auto-finish; burnt orange when available), New Game and More (How to Play, Settings… and About Solitaire) — or five, with Restart after Undo, when Settings ▸ Restart button is on (see "Restart"). On a phone held sideways the header folds into the bar, whose buttons are then 52 pt.

Cards are drawn in SwiftUI, not images, in the face and back the player has chosen (see "Card styles"): a rounded rectangle with a hairline border and a 1 pt shadow, corner index top-left, a large suit below it.

The table is a dark green gradient that the card faces stay readable against in light and dark mode. Card faces do not invert in dark mode. Moves animate with a 0.2 s `.easeOut`; flips use a 0.25 s rotation on the Y axis. All motion is skipped when `accessibilityReduceMotion` is on.

## Colours and dialogs

Decided from the 1.1 mockups (design canvas, "1.1 — every dialog and screen").

- **Orange, not gold.** Burnt orange #CC5500 is the one accent: as a fill it always carries
  near-black text #0A0A0A (5:1), like the Finish button, and it colours switches and selection
  rings. Orange *text* uses a shade that reads on its background: #B04800 on light sheets
  (5.2:1 on white) and #FF8A3D on dark ones (7.8:1 on #141414). The app's accent colour (system
  buttons such as Done, links) is #B04800 in light appearance and #FF8A3D in dark.
- **The win sheet and the "lose this game?" questions are dark cards** over the table dimmed to
  40 % (a black scrim at 60 %): card #141414 with a #2A2A2A hairline, 24–28 pt corners, title
  #F4F1EC, body #C8C3BD, small Space Mono labels #9A9590. Buttons are at least 44 pt tall: the
  main one orange with dark text, others outlined (#4A4642) with light text. They replace the
  system alert and sheet on every platform. Return chooses the main button and Esc cancels;
  VoiceOver treats the card as modal and starts at its title. Tapping the dimmed table outside a
  question cancels it; outside the win card it does nothing.
- **Win card:** the draw mode as a small label, "You won!", SCORE large in Space Mono, then the
  figures MOVES, TIME, PASSES and UNDOS, a "New Top 10" badge when the win made the list (see
  "Scores"), and the buttons — with **Top 10** beside the other mode, then **New Game · Draw n** in
  the same mode (orange), **Draw m instead**, and **Close**. On iPhone it sits at the bottom of
  the screen; on iPad, the Mac and a phone held sideways it is centred, at most 480 pt wide, with
  its buttons in one row — Close and the other mode at their labels' width, the main button taking
  the rest so its label is never cut.
- **Question cards:** a small label (NEW GAME, or DRAW 1 → DRAW 3), the title, the message, then
  **Cancel** (outlined) and the confirming button (orange), centred.
- **Settings, About and How to Play** stay system sheets and forms, with the orange accent.

## Card styles

The player chooses a card face and a card back, independently, in Settings (see "Settings, About and
the More menu"). Four of each ship; the defaults are the original look, so nothing changes for a
player who never opens Settings. Everything is drawn in SwiftUI from these rules — no image files —
and every place a card appears uses the chosen style: the board, a drag in progress, the win
cascade (its cached card images are keyed by style), and the Settings previews.

Faces (rank and suit sizes are fractions of the card width):

| Face | Look |
| --- | --- |
| **Classic** (default) | White face; rank in the rounded system font, semibold, × 0.36, small suit × 0.28, top-left; large suit × 0.62, bottom-right; red and black from the asset colours |
| **Big Index** | White face; a heavier, larger corner index — black weight, rank × 0.37, small suit × 0.30 — in pure black and a bright red (#D0021B); large suit × 0.66, centred |
| **Vintage** | Cream face (#FBF4E4) with a fine inner frame (5 % inset); rank in the system serif (New York), bold; ink #1F1F1F and deep red #9E1B32; large suit centred |
| **Night** | Dark face (#262626, border #3A3A3A) with light ink: #EDEAE4 for spades and clubs, #FF7A7A for hearts and diamonds; layout as Classic |

Backs (each a white or tinted card with a patterned panel inset by 7 % of the width):

| Back | Look |
| --- | --- |
| **Classic Blue** (default) | White card; blue panel (#1D4E9C) with a white diagonal lattice at 30 % |
| **Burnt Orange** | The same lattice on #CC5500 |
| **Racing Green** | Cream card (#F7F1E3); green panel (#1F5E3A) of small cream diamonds at 35 %, with a cream inner frame line |
| **Art Deco** | Cream card (#F7F1E3); navy panel (#1B2A4A) with gold rays (#C9A227 at 75 %) fanning up from the middle of the bottom edge — 4° wide, every 12° — and a gold inner frame line |

Rules every style keeps:

- **Readable when fanned.** A face-up card under another shows only its top strip, which is never
  less than 0.24 × card height (decision D1). Each face's corner index — rank and small suit — fits
  inside that strip at every card size: the index is placed by its capitals, whose tops sit
  0.07 × card width below the card's edge, the same margin as at its left (text's own space above the capitals would otherwise
  push it about 0.09 × width lower). A unit test checks, with the platform's real font metrics,
  that every face's index ends within the strip.
- **Red and black stay distinct** (Klondike alternates them): each face has exactly two ink colours,
  one for hearts and diamonds and one for spades and clubs, and they differ in lightness, not hue alone.
- **No inversion in dark mode:** faces and backs look the same in light and dark appearance; Night
  is a choice, not an automatic mode.
- **Live:** changing a face or back restyles every card at once, including the game in progress.

## Scoring

Every game starts at **0** (decision 2026-10-03, U24; 1.0 builds started at 600 and took time
off the score). The score is a **play score**, plus a **time bonus** once the game is won. Both
are worked out from the game itself — never kept as a running total — so they cannot drift from
the board:

| Play score | Points |
|---|---|
| Each card on a foundation | +5 (so a card taken back off costs 5) |
| Each complete suit (13 on a foundation) | +35 (a whole suit is worth 100) |
| Each undo | −3 (and the undone move's points go with it) |
| Each redeal (pass after the first) | −100 |
| Floor | 0 — of the total, so a cost taken early is still owed when points come later |

| Time bonus, on a win only | Points |
|---|---|
| Up to 1:00 | 600 |
| From 1:00 | less 1 a second from 1:00 to 2:00, 2 from 2:00 to 3:00, and so on |
| Floor | 0 (from 5:00) |

A one-pass win with no undos earns 400 in play, so it scores 1000 under a minute, 940 at 2:00,
820 at 3:00, 640 at 4:00 and 400 from 5:00. Auto-finish moves score like any others. **SCORE**
leads the header (SCORE, TIME, MOVES and the draw chip, on every size) and shows the play score
while the game goes on — time does not touch it; VoiceOver reads "Score 245". Once won it shows
the whole score. The win card shows the whole score large, "PLAY 294 + TIME BONUS 360" under it
(VoiceOver: "Score 654, play 294 plus time bonus 360"), then MOVES, TIME, PASSES and UNDOS. A game saved before undos were counted resumes with none.

## Scores: your Top 10 and Game Center

Only **wins** count. Each win is recorded twice:

- **Your Top 10** — two lists, **Draw 1** and **Draw 3**, each the ten best wins in that mode
  (normal and Hard Core together, Hard Core marked **HC**), with score, time and date; the higher
  score first, and on a tie the earlier win. Kept on the device and synced across the player's
  devices through iCloud's key-value store (merged, never overwritten: the best ten of both
  copies); without iCloud the lists stay on the device.
- **Game Center** — four leaderboards, one per draw mode and difficulty, in one set "Solitaire":
  `com.oneoffendeavors.solitaire.draw1`, `.draw3`, `.draw1.hardcore`, `.draw3.hardcore` (integer
  scores 0–1000, each player's best kept, highest first; created by `tools/asc.py gamecenter`).
  The player is signed in at launch through Game Center's own prompt; signed out, nothing is
  submitted and the game is unaffected. Prerelease builds (TestFlight) use the same Game Center as
  the store: their scores are visible to the player's Game Center friends.

**Scores** (a tile on the More card; a sheet on iPhone and iPad, its own window on the Mac) is a
dark screen: a **Draw 1 / Draw 3** switch (opening on the current game's mode), **Your Top 10**
for that mode (the latest win highlighted; "No wins yet" when empty), then that mode's two Game
Center boards with the player's best and rank ("Not signed in" or "No score yet" otherwise) —
each opens the board in Game Center — and a footnote on iCloud.

**The win card** shows a **New Top 10 · #3 in Draw 1** badge (orange outline) when the win made the
list, and a **Top 10** button that opens Scores on that mode.

Tests never touch the player's Top 10, iCloud or Game Center: UI tests use their own settings
suite with iCloud and Game Center off.

## Win animations

A won game plays one of four animations over the board, then the win card appears (a tap skips
straight to it). The player chooses in Settings ▸ **Win animation**: **Cascade** (the default),
**Rainfall**, **Decay**, **Shuffle**, **Random** (one of the four, settled per game) or **None**.
With Reduce Motion on, or None, nothing plays and the win card comes at once; VoiceOver users get
the win card at once as before. Saved as `winAnimation`; an unknown value reads as Cascade.

- **Cascade** — the classic: kings first, each card leaps off its pile, bounces along the bottom
  leaving a trail, and leaves the screen; the trail stays.
- **Rainfall** — kings first round the four piles, one card every 0.12 s drops from its pile with a
  slight sway and spin, straight off the bottom.
- **Decay** — each pile dissolves from the top down: the top card is eaten away along ragged,
  noise-shaped edges with a thin burnt-orange rim, the card beneath showing through the holes; each
  card over 0.55 s, the piles a quarter-second apart, until all four are gone. The dissolve is a Metal
  shader (fractal noise against a rising threshold), so it is continuous at the display's frame
  rate; building needs Xcode's Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`).
- **Shuffle** — the cards gather into two half-piles, riffle into one deck, turn face down and
  slide onto the draw pile, where they stay. It is only an animation: the next game is dealt as
  usual.

In every one the foundations keep their cards until each card's turn comes.

## Hard Core

A harder game with limited passes through the deck: **one in Draw 1** (no redeal at all) and
**three in Draw 3** (two redeals). It is a property of the deal, like the draw mode, saved with the
game (a save without it is a normal game).

- **Turning it on or off** is the **Hard Core** switch in Settings ▸ Game, which shows the current
  game's mode. Changing it deals a new game in the other mode — asked first when a game is in
  progress ("Turn on Hard Core?" / "Turn off Hard Core?", label HARD CORE; **Start Hard Core** /
  **Start New Game** and **Cancel**), unless "Ask before ending a game" is off. Settings closes
  first so the question shows over the game; Cancel leaves the game and the switch as they were.
  New Game, the draw chip and the win card keep the current game's Hard Core mode.
- **On the table:** the draw chip reads **DRAW 1 · HC** (VoiceOver: "Draw one, Hard Core"), and the
  win card's label **DRAW 1 · HARD CORE**. When the passes are used up — stock empty, waste not —
  the stock's outline shows ✕ instead of the redeal arrow and tapping it does nothing (VoiceOver:
  "Stock, empty. No passes left"). Undo still works.
- A saved Hard Core game with more passes than its limit is damaged and is not resumed.

## Settings, About and the More menu

**More** (the fourth button of the bottom bar) opens a dark card of tiles on every platform (spec
"Colours and dialogs"; option B of the 1.1 mockups): **How to Play**, **Scores**, **Settings** and
**About**, each an orange icon over its label on a #1E1E1E tile, with Close below. On a phone held upright the card rises from the bottom; elsewhere it is centred.
Choosing a tile closes the card and opens that screen; Close, Esc or a tap on the dimmed table
just closes it. On
the Mac, ⌘, and Solitaire ▸ Settings… open Settings, and Solitaire ▸ About Solitaire opens About.

**Settings** — a sheet on iPhone and iPad, the Settings window on the Mac:

- **Game:** resume the game in progress at launch, **Hard Core** (see "Hard Core"; shows the current
  game's mode and changing it deals a new game), and **Draw pile on the right** (off by default:
  the stock and waste sit on the left). Turning it on mirrors the top row at once, the game in
  progress included; cards that are moving finish where the new layout puts them. Then **Ask
  before ending a game** (on by default; see "New games and the draw mode"), and **Restart button**
  (off by default; see "Restart"). (The draw mode is not a setting: the draw chip switches it.)
- **Card face:** the four faces as tappable previews (an ace of hearts in each), the current one
  ringed in burnt orange (#CC5500).
- **Card back:** the four backs as tappable previews, ringed the same way.
- A live preview at the top: the chosen back beside two cards in the chosen face.

Changes apply immediately and are saved at once.

## New games and the draw mode

A game is **in progress** once at least one move (a draw included) has been made and it is not won.
Only a game in progress is ever asked about; a fresh deal or a won game is replaced without a
question, because nothing would be lost. With **Ask before ending a game** off (Settings ▸ Game), a
game in progress is replaced without a question too: every way of starting a new game (New Game,
⌘N, the draw chip, the Mac's File and Game menu items, and Hard Core once it exists) deals at once.

- **New Game** (the bar button, ⌘N, File ▸ New Game) deals at once in the current game's draw
  mode. In progress, it first asks: "Start a new game? This one will be lost." — **New Game** /
  **Cancel**. There is no draw-count chooser.
- **The draw chip** ("DRAW 1" / "DRAW 3", in the header, or in the bar on a phone held sideways)
  is a button that switches to the other mode by dealing a new game in it. In progress, it first
  asks: "Switch to Draw 3? This starts a new game, and the current one will be lost." —
  **Start New Game** / **Cancel**. VoiceOver reads it as "Draw 1", hint "Switches to Draw 3 and
  starts a new game".
- **On the Mac:** Game ▸ Draw Three switches as the chip does; File ▸ New Game: Draw 1 / Draw 3
  deal in that mode; each asks first when a game is in progress.
- **The win card** offers New Game in the same mode and the other mode — the game is over, so
  nothing is asked.

The mode of the last deal — draw count and Hard Core — is remembered and used for the next New
Game and the next launch's fresh deal. Cancel leaves the game, its mode and its timer untouched. Asking stops auto-finish
where it is, so a game cannot be won behind the question; Finish is offered again after Cancel.

**About** — a sheet on iPhone and iPad, its own window on the Mac (replacing the standard About
panel):

- the app icon, **Solitaire**, and **Version 1.1 (build)** from the bundle;
- one line: "Klondike, made by One Off Endeavors. No ads, no tracking, nothing to sign up for. Your
  Top 10 syncs through your own iCloud, and your wins go to Game Center when you're signed in."
  (1.0 said "nothing leaves your device", untrue once 1.1 added iCloud and Game Center);
- links: **One Off Endeavors** (https://oneoffendeavors.com), **Privacy policy**
  (https://oneoffendeavors.com/solitaire/privacy/), **Support and feedback**
  (https://oneoffendeavors.com/solitaire/support/, the app's support page; the App Store's Support URL too);
- **Acknowledgements:** Space Mono, © 2016 The Space Mono Project Authors, SIL Open Font License 1.1,
  with the licence's full text one tap away;
- **© 2026 One Off Endeavors**.

A link opens in the user's default browser. The app's own code still makes no network connection
(on the Mac it remains sandboxed without a network permission); iCloud and Game Center are the
system's services.

## Restart

An option (decision 2026-10-03, U25): **Settings ▸ Game ▸ Restart button**, off by default. With it
on, a **Restart** button (↺, `arrow.counterclockwise`) sits in the bottom bar right after Undo —
Undo, Restart, Finish, New Game, More — and the Mac's Game menu gains **Restart Game** (⌘R).

- Restart deals **this same game again from the start**: the same cards (the same seed), draw
  mode and Hard Core, with moves, time, passes and undos back to none and undo history cleared.
  It works at any point, a won game included; on a fresh deal (no move yet) it is disabled.
- A game in progress is asked about first, as for a new game (and not when Ask before ending a
  game is off): kicker **RESTART**, "Restart this game?", "You’ll play the same deal again from
  the beginning. A restarted game scores 0 and doesn’t count toward your Top 10 or Game Center."
  — **Restart** / **Cancel**.
- A restarted game is marked (`isRestarted` in the state, saved with it; older saves were never
  restarted). While marked, its score — header and win card — is **0**, with no other label, and
  its win goes to **neither the Top 10 nor Game Center** and gets no "New Top 10" badge. Restarting
  again keeps the mark; New Game, the draw chip, the Mac's draw items and the Hard Core switch deal
  a new game, which clears it.

## Persistence and settings

The game in progress is saved as JSON to `Application Support/Solitaire/game.json` through an actor that writes atomically. It saves after every applied move, on every timer tick divisible by five, and on scene phase leaving `.active`. Nothing is written to iCloud or the network.

On launch the app decodes that file, checks it holds 52 distinct cards and is not already won, and resumes it; anything invalid is discarded silently and a fresh game is dealt. The undo stack is not persisted — a resumed game starts with undo empty.

Settings live in `UserDefaults` via `@AppStorage`: the draw count of the last deal (default 1), a preference for whether to resume or always deal fresh (default resume), the card face (default Classic), the card back (default Classic Blue), the draw pile's side (default left) and whether to ask before ending a game (`askBeforeEndingGame`, default yes). An unknown or invalid stored value falls back to the default. New games deal in the remembered draw count; the draw chip changes it (see "New games and the draw mode").

On macOS, window size and position restore through the standard scene restoration; the game itself is not tied to a particular window size. The game window is the app: closing it quits Solitaire (saving as any quit does), and any How to Play, About or Settings window closes with it — so a menu command can never act on a game that is not on screen.

## Acceptance criteria and open decisions

Build the engine and its tests before any view. The app is done when all of these pass.

- [ ] A new deal always produces 52 distinct cards, 28 in the tableau with exactly 7 face up, and 24 in the stock.
- [ ] Every legal move listed in the rules succeeds and every illegal one is refused, covered by unit tests on `canMove`.
- [ ] Draw 3 leaves only the waste's top card playable; redeal restores the stock in reverse order.
- [ ] Undo from any point returns the exact previous board, move count and passes, including face-up flips and redeals, for 100 random moves from a fixed seed — with the undo count rising by one each time.
- [ ] A game played to a win from a known-solvable seed sets `isWon` and shows the win card with the move count and time.
- [ ] Tap-to-move never produces a no-op, and dragging a king onto an empty column from the bottom of another column is possible by drag but not offered by tap.
- [ ] Force-quitting mid-game and relaunching restores the same board, move count and elapsed time.
- [ ] The board lays out without clipping on iPhone SE portrait, iPhone Pro Max landscape, iPad split view at one third width, and a 600 pt wide Mac window.
- [ ] Instruments shows no dropped frames while dragging a 13-card run on the oldest supported device.
- [ ] The app builds with no third-party packages and its own code makes no network calls (the Mac app has no network entitlement; iCloud and Game Center go through the system).

Open decisions for whoever builds it: whether to ship a win animation (a cascade of cards is the classic, and SpriteKit would be the only added framework), whether to add a hint button, and whether the Mac version gets a full-screen felt background or stays in a bordered window.

## Decisions

Recorded as they are made; each overrides anything above it conflicts with.

| Date | Decision |
| --- | --- |
| 2026-09-27 | Bundle identifier `com.oneoffendeavors.solitaire`. |
| 2026-09-27 | Open decisions: the win animation is a SwiftUI card cascade (no SpriteKit); no hint button in v1; the Mac version stays in a bordered window. |
| 2026-09-27 | Tapping or clicking a card on a foundation does nothing. Taps send cards toward the foundations; taking one back down is drag-only, so a missed tap never undoes progress. |
| 2026-09-27 | Once the game is won, no move or draw is allowed, so a won game cannot be un-won. |
| 2026-09-27 | An invalid stored draw count is clamped by the store before dealing; the engine's `newGame` keeps its 1-or-3 precondition. A resumed save must also have exactly 4 foundations and 7 columns. |
| 2026-09-27 (wording 2026-09-30) | Any build distributed outside this Mac (TestFlight, App Store, a shared `.app`) must not let a debugger attach: on the Mac the `com.apple.security.get-task-allow` entitlement is absent; on iOS/iPadOS `get-task-allow` is `false` (App Store signing always writes the key, set to false). Local development builds allow it, and that is fine for development. `tools/check-release.sh` enforces this before every upload. |
| 2026-09-27 | (Superseded 2026-10-01 by the draw chip.) New games ask for the draw count everywhere (toolbar, win sheet) except ⌘N, which the spec lists as a direct shortcut: it deals at once in the remembered mode. |
| 2026-09-27 | "Same elapsed time" after a relaunch: quitting normally (⌘Q on the Mac, or iOS sending the app to the background) saves on the spot, so the time comes back exactly. A true force quit gives the app no chance to save, so the time comes back to the last save — at most five seconds earlier, the spec's own save cadence. |
| 2026-09-27 | Layout D1 — short, wide boards (phone landscape, short Mac windows): card width is the spec's width rule, capped by height so the top row plus a column of six face-down cards under a nine-card run (K→5) fits with its face-up fan no smaller than 0.24 × card height (readable; 0.2 until the corner index gained a top margin on 2026-10-01). Longer runs squeeze further. Where height is plentiful the width rule is unchanged. |
| 2026-09-27 | Layout D2 — "compressed layout": on touch, when cards would be narrower than 44 pt, gaps drop to the 4 pt minimum and each card's tap area widens to its whole column slot. |
| 2026-10-01 | Direction A, chosen from mockups (design canvas "Solitaire layout mockups"): one layout for iPhone, iPad and Mac. Phone-width boards (under 500 pt) use 3 pt column gaps and 4 pt side margins, for cards about 9% larger. A row gap of 0.8 × card width separates the top row from the columns, capped at 16 pt on a touch board held sideways. Header (moves, time, draw mode; Space Mono, SIL OFL) over the board; a bottom bar with four labelled 60 pt buttons (Undo, Finish, New Game, More) on every platform, the Mac included; Finish is burnt orange (#CC5500) when auto-finish is available. On a phone held sideways the header folds into the bar (52 pt buttons), which keeps the cards about as large as before. |
| 2026-10-01 | Card styles, Settings and About (plan agreed from the "Cards" and "Settings and About" mockups): faces Classic, Big Index, Vintage and Night; backs Classic Blue, Burnt Orange, Racing Green and Art Deco (Art Deco replaced Night Pinstripe after a look on TestFlight); chosen independently, Classic + Classic Blue by default, applied live. Four Colour was left out: blue diamonds and green clubs blur Klondike's red/black alternation. More offers How to Play, Settings… and About Solitaire; Draw Three and Resume move into Settings, and the new-game chooser keeps only Draw 1 / Draw 3. About links open in the browser; the app still has no network code. Copyright line: "© 2026 One Off Endeavors". |
| 2026-10-01 | Corner index margin (after a look at TestFlight build 202610012043): the index sat almost on the card's top edge. It now has a 0.07 × card width margin above it, as at its left, at full size; to keep D1's promise that it reads in the tightest fan, the minimum face-up fan rises from 0.2 to 0.24 × card height. Portrait boards are unchanged; on a phone held sideways or a short Mac window cards come out about 8 % smaller. |
| 2026-10-01 | Draw chip and direct New Game (after U12 on TestFlight): the header's draw mode becomes a button that switches mode by dealing a new game, and New Game deals at once in the current mode — no chooser. Both ask before replacing a game in progress (a move made, not won), never otherwise. Settings drops the draw picker and the chip drops "· NEXT n": one place to change the mode, always showing the game being played. |
| 2026-10-01 | Closing the Mac's game window quits the app (U13 review): with the window gone, ⌘N's question had nowhere to appear and surfaced later. |
| 2026-10-02 | Draw pile on the right (tester feedback): a setting mirrors the top row — stock and waste on the right, foundations on the left; left stays the default. Only the top row mirrors (the tableau is the same either way), and the Draw 3 fan opens into the empty column (on the right the playable card stays beside the stock, so the cards beneath it still show their corner index). |
