# Solitaire

Classic Klondike solitaire for **Mac, iPhone and iPad** — one SwiftUI app, one shared rules
engine, one adaptive board. No ads, no in-app purchases, no accounts and no network access: the
Mac app is sandboxed without a network permission, and nothing leaves the device.

- Draw one or draw three, unlimited redeals
- Tap or click to send a card to its best spot, or drag it exactly where you want it
- Undo (up to 300 steps), auto-finish, and a card cascade when you win
- Four card faces and four card backs to choose from (Settings, under **More**)
- Your game is saved as you play and picks up where you left off
- VoiceOver labels on every card and empty pile; Reduce Motion turns off all animation

## How to play

**Goal:** move all 52 cards onto the four foundations (the outlined spaces marked **A**, top
right), one pile per suit, from ace up to king.

**The deal:** seven columns; column 1 has one card, column 7 has seven. Only the last card of each
column is face up. The other 24 cards are the **stock** (top left, or top right if you put the draw
pile on the right in Settings); cards you draw go face up on the **waste** next to it.

**Moves:**

- **To a foundation:** an ace onto an empty foundation, then the same suit one rank higher
  (A, 2, 3 … K). Cards go up from the waste or from the bottom of a column.
- **Between columns:** a card goes onto a card one rank higher of the opposite colour (a red 7
  onto a black 8). You can move a whole face-up run together, from any face-up card down.
- **Empty column:** only a king, with any run on it.
- **Back from a foundation:** you can drag a foundation's top card back onto a column, under the
  same colour and rank rule.
- When a move uncovers a face-down card at the bottom of a column, it turns over by itself.

**The stock:** tap it to draw — one card, or three in *Draw 3* mode, where only the top card of the
waste can be played. When the stock is empty, tap it again to turn the waste back over (no limit).

**Winning:** once the stock and waste are empty and every card is face up, **Finish** lights up
orange in the bar and plays the rest for you. There is no score and no losing — if you are stuck, undo or deal again.

### Controls

| | Mac | iPhone and iPad |
|---|---|---|
| Send a card to its best spot | click (double-click works too) | tap |
| Place a card exactly | drag | drag |
| Draw / turn the waste over | click the stock, or **Space** | tap the stock |
| Undo | **⌘Z** or **Undo** in the bar | **Undo** in the bar (⌘Z with a keyboard) |
| New game (same draw mode) | **⌘N**, or **New Game** in the bar | **New Game** in the bar |
| Switch Draw 1 ↔ Draw 3 (deals a new game) | click **DRAW 1 / DRAW 3** in the header, **Game ▸ Draw Three**, or **File ▸ New Game: Draw 1 / Draw 3** | tap **DRAW 1 / DRAW 3** in the header |
| Auto-finish | **⌘↩︎** or **Finish** in the bar (orange when available) | **Finish** in the bar (orange when available) |
| How to Play | **Help ▸ Solitaire Help** (⌘?), or **More ▸ How to Play** | **More ▸ How to Play** |
| Settings: resume, card face and back | **Settings (⌘,)** or **More ▸ Settings…** | **More ▸ Settings…** |
| About | **Solitaire ▸ About Solitaire**, or **More ▸ About Solitaire** | **More ▸ About Solitaire** |

A card with nowhere to go gives a little wiggle. Tapping a card on a foundation does nothing, so a
missed tap never pulls a card back down; drag it if you mean to. Once you win, the game is locked:
nothing moves and undo is off.

Starting a new game or switching draw mode while a game is under way asks first, since the current
game would be lost; on a fresh deal or after a win it just deals. Turn off **Ask before ending a
game** in Settings and it never asks.

### Saving and settings

The game in progress is saved after every move and every few seconds, and when you quit or switch
away; it resumes at the next launch (undo history starts fresh). Quitting normally keeps the time
exactly; a force quit returns to the last save, at most five seconds earlier. On the Mac, closing the
game window quits Solitaire (and saves).

The draw mode of your last deal is remembered (default: one card). Settings: whether to resume the game in
progress at launch (default: yes), whether the draw pile sits on the right (default: left; the
foundations swap to the left), whether to ask before ending a game in progress (default: yes),
and the card face (Classic, Big Index, Vintage, Night; default
Classic) and card back (Classic Blue, Burnt Orange, Racing Green, Art Deco; default Classic
Blue). Face and back change every card at once, including the game in progress.

Where things live — inside the app's sandbox:

- the game: `Library/Application Support/Solitaire/game.json` (a small versioned JSON file)
- the settings: the app's standard UserDefaults

## Requirements

- macOS 14 or later, iOS / iPadOS 17 or later
- To build: Xcode 16 or later (developed with Xcode 27 on macOS 27), Swift 6

## Building and running

The Xcode project is **generated** from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is not committed. Change project settings in `project.yml`, never in Xcode's project editor —
the next generation would overwrite them.

**On the Mac, with `make`** (no Xcode IDE needed; `make help` lists every target):

```bash
make run              # generate the project, build the Mac app, launch it and stream its logs
make test             # engine tests + the app's unit tests
make uitest           # UI tests — leave the Mac alone while they run
make install          # build for your iPhone or iPad and install it (needs .devteam and .device)
make clean
```

The first `make` builds the XcodeGen pinned in `.xcodegen-version` (about a minute, once) into
`~/Library/Caches/apple-xcodebuild/`, the cache the skill below uses too. A tag that has moved off
the pinned commit is refused, never built.

**From a Linux container** (how this app was built), with the `apple-xcodebuild` skill driving a
Mac over SSH:

```bash
X=~/.claude/skills/apple-xcodebuild/scripts
python3 $X/xc-doctor.py                         # is the Mac ready?
python3 $X/xc-build.py --adhoc                  # iOS Simulator + macOS
python3 $X/xc-run.py --platform macos           # or --platform ios-sim --device "iPhone 18 Pro"
python3 $X/xc-shot.py --platform macos          # a screenshot of the running app
```

**Signing.** Signing settings are per developer, so they live in gitignored files:

```bash
echo XXXXXXXXXX > .devteam          # your Apple team ID: automatic signing (needed for a device)
echo 'My iPhone' > .device          # the device to install on and profile (see make devices)
```

`make` signs the Mac app with `.signid` (a named identity) if present, else your team, else ad-hoc;
device builds always use the team. `make install` builds for the named device, so the first time
it registers that device with your team and creates its provisioning profile.

At the Mac, that uses your login keychain and the Apple ID signed in to Xcode (Settings ▸
Accounts). **Over SSH** neither is usable, so on a build Mac `make` reads a per-machine
`$HOME/.config/appstoreconnect/api.env` (override with `ASC_ENV=`) and then unlocks a dedicated
signing keychain and provisions with an App Store Connect API key instead:

```make
ASC_KEY_ID=XXXXXXXXXX                          # App Store Connect ▸ Users and Access ▸ Integrations
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=/Users/me/.config/appstoreconnect/AuthKey_XXXXXXXXXX.p8
SIGNING_KEYCHAIN=/Users/me/Library/Keychains/signing.keychain-db
SIGNING_KEYCHAIN_PASS_FILE=/Users/me/.config/appstoreconnect/keychain-pass   # chmod 600
```

The signing keychain holds your Apple Development identity and Apple's WWDR G3 intermediate, with
its key opened to `codesign` (`security set-key-partition-list`). Distributed builds must not let a
debugger attach (see the spec's decisions).

**TestFlight.** The App Store Connect app record is **One Off Solitaire** (bundle ID
`com.oneoffendeavors.solitaire`, iOS and macOS). With the API settings above in place:

```bash
make archive      # Release archives for iOS and the Mac; build number = UTC time (must rise per upload)
make export       # Apple signs them for the App Store, then tools/check-release.sh checks the result
make upload       # uploads exactly those two packages
make testflight   # recent builds and whether Apple has finished processing them
```

The iOS archive is left unsigned and Apple signs it at export (a signed one would need a
development profile, which needs a registered device); the Mac archive is signed with your team so
it carries the sandbox entitlement. `check-release.sh` refuses to pass a package that is not
signed Apple Distribution, that a debugger could attach to, or that lacks the privacy manifest.
Testers install through the TestFlight app — no Developer Mode, no device registration. The
privacy policy the store links to is <https://oneoffendeavors.com/solitaire/privacy/>.

**Profiling.** `make profile` installs the Debug build on your device, launches it on a Debug-only
position — a 13-card King→Ace run next to an empty column, with its own save file and settings so
it never touches your game — and records **Animation Hitches** for 30 seconds (`TIME=60s` for
longer) while you drag the run back and forth. The trace opens in Instruments when it ends (`OPEN=no` just saves it in `build/traces/`).
`make profile-mac` does the same on the Mac. Hitches are only measured on real hardware, not the
simulator. The Debug build is slower than Release, so a clean trace holds for both.

## Testing

| Suite | What it covers | Run it |
|---|---|---|
| Engine (`Packages/SolitaireEngine`) | every rule, the seeded deal, draw/redeal, tap-to-move, auto-finish, a full winning game | `swift test` in the package — on macOS or Linux (`docker run --rm -v "$PWD":/pkg -w /pkg swift:6.1 swift test --scratch-path /tmp/build`) |
| App unit tests | the store (undo, clock, drag), layout at the spec's sizes, VoiceOver roles, saving and resuming | `make test`, or `xc-test.py --platform macos` / `--platform ios-sim` |
| UI tests | the running app: winning and the win sheet, drag vs tap, draw/undo, menus, the draw-count choice, force-quit and relaunch, exact time after quitting | `make uitest`, or the same `xc-test.py` commands |

Every behaviour has a test that was shown to fail with that behaviour broken.

**macOS UI tests** need, once, on the Mac:
`sudo automationmodetool enable-automationmode-without-authentication` — otherwise each run asks for
Touch ID or an Apple Watch. Leave the Mac idle while they run: macOS won't bring the app to the
front while you are using another app, and those tests then fail with "Running Background". UI
tests never touch your real game or settings; they use their own save file and settings.

## Project layout

```
spec.md                          the specification, with a Decisions table that overrides it
project.yml                      XcodeGen spec (the .xcodeproj is generated)
Makefile                         build, run, test, install and profile on the Mac
tools/xcodegen                   runs the pinned XcodeGen, building it once
tools/make-icon.swift            draws the app icon (swift tools/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset)
tools/check-release.sh           checks exported packages before upload
tools/asc.py                     App Store Connect API: builds, bundle ID
Packages/SolitaireEngine/        the rules: pure Swift, no UI, tested on macOS and Linux
Sources/Solitaire/
  GameStore.swift                the only thing that changes the game: intents, undo, clock, saving
  Persistence.swift              the save file, resume checks, launch decision
  SolitaireApp.swift             app, menus and shortcuts, settings
  ContentView.swift, GameBar.swift   window, header and draw chip, bottom bar, More, win sheet
  HowToPlayView.swift            the in-app help
  Board/                         layout metrics, card drawing, drag and tap, win cascade
  UITestScenario.swift           Debug-only positions for UI tests and profiling
Tests/SolitaireTests/            unit tests (Swift Testing)
Tests/SolitaireUITests/          UI tests (XCUITest)
Resources/Fonts/                 Space Mono (header figures), with its licence (SIL Open Font License 1.1)
Resources/PrivacyInfo.xcprivacy  Apple privacy manifest: no tracking, no data collected
```

## Design decisions

`spec.md` is the source of truth. Its **Decisions** table records every choice made while building
— for example how the board fits short screens, why foundation taps do nothing, why ⌘N deals
straight away, and what "same elapsed time" means after a force quit.

## License

MIT — see [LICENSE](LICENSE).
