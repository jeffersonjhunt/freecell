# Solitaire 1.1 — plan

Approved 2026-10-02. Each unit after U15 runs the full lifecycle: spec change first, a branch,
tests (with negative checks), adversarial review dispositioned by the owner, TestFlight, an
on-device check, then the merge. 1.1 ships to **TestFlight only**.

## Units

| Unit | What | Depends on |
|---|---|---|
| U15 Design pass | Mockups of every dialog and screen on the design canvas, approved before code | — |
| U16 Colours and dialogs | Accent colour becomes the Finish orange (#CC5500); every dialog rebuilt to the approved mockups | U15 |
| U17 Skip confirmations | Settings ▸ "Ask before ending a game" (on by default): New Game, the DRAW chip and the Hard Core switch | — |
| U18 Pass counter | The engine counts passes through the deck, saved with the game (a 1.0 save opens with 0); shown on the win sheet (not in the header) | U16 |
| U19 Hard Core | Settings switch; changing it starts a new game (asks mid-game). Draw 1: 1 pass; Draw 3: 3 passes. The DRAW chip reads DRAW n · HC; ✕ "No passes left" on the stock | U18 |
| U20 Scoring | Rules below; SCORE live in the header and on the win sheet; undos counted and saved | U18 |
| U21 Top 10 + Game Center | Two Top 10 lists (Draw 1, Draw 3) synced via iCloud; four Game Center leaderboards; scores screen from More; App Store Connect setup | U19, U20 |
| U22 Win animations | Mockups, then the chosen animations plus None in Settings; Reduce Motion always means none | — |
| U23 Release 1.1 | Version 1.1, What's New, privacy policy and App Store privacy answers | all |

## Scoring

| Rule | Points |
|---|---|
| Start | 600 |
| Card placed on a foundation | +5 |
| Completed suit | +35 (a whole suit is worth 100) |
| Card taken off a foundation | −5, and −35 if it breaks a completed suit |
| Undo | takes back what the undone move scored, then −3 |
| Redeal (waste turned back over) | −100; the first trip through the stock is free |
| Time | −1 per second from 1:00 to 2:00, −2 per second from 2:00 to 3:00, and so on |
| Floor | 0 |

A one-pass win in under a minute scores 1000. The score is derived from the game itself, so it
cannot drift from the board; auto-finish moves score like any others.

## Scores

- **Top 10:** two lists, Draw 1 and Draw 3, each the ten best **wins** in that mode (normal and
  Hard Core together, Hard Core badged HC), with score, time and date. Synced across the
  player's devices through iCloud; without iCloud they stay on the device.
- **Game Center:** four leaderboards — Draw 1, Draw 3, Draw 1 · Hard Core, Draw 3 · Hard Core —
  grouped in one set (IDs `com.oneoffendeavors.solitaire.draw1`, `.draw3`, `.draw1.hardcore`,
  `.draw3.hardcore`). Each win is submitted to the board for its mode and difficulty. Game Center
  keeps each player's best per board, which is why Hard Core has boards of its own.
- To confirm in U21: how leaderboards behave for TestFlight testers before 1.1 is on the store.

## Decisions

- Hard Core passes: Draw 1 has no redeal; Draw 3 has two. Out of passes: ✕ on the stock, undo
  still allowed; no "game over" detection in 1.1.
- The pale gold accent (#F3C447) is what made dialogs hard to read; it is replaced by #CC5500.
- Win animations: mockups first; "Random" decided then.

## Design (U15, approved 2026-10-02)

Mockups: the design canvas "Solitaire layout mockups", section "1.1 — every dialog and screen".

- **Header, every size:** SCORE, TIME, MOVES and the DRAW chip on one line (DRAW n · HC in Hard
  Core). Passes are not in the header; they show on the win sheet.
- **Win sheet and the "lose this game?" questions:** dark cards (#141414, hairline #2A2A2A) over a
  dimmed table, not system sheets or alerts. Win: draw mode (and Hard Core), "You won!", the score
  large in Space Mono, a "New Top 10" badge when it qualifies, MOVES / TIME / PASSES / UNDOS, then
  New Game in the same mode (orange), the other mode, Top 10, Close.
- **Orange instead of the gold accent:** fills #CC5500 with near-black text (as Finish); orange
  text #B04800 on light sheets and #FF8A3D on dark cards, because #CC5500 text on white is only
  4.3:1.
- **Settings, About, How to Play:** system sheets with orange accents. Settings gains Hard Core,
  "Ask before ending a game" and a Win animation row; How to Play gains Scoring and Hard Core.
- **Scores:** a dark sheet with a Draw 1 / Draw 3 switch, the Top 10 (today highlighted, HC
  badges) and the mode's two Game Center boards with best score and rank.
