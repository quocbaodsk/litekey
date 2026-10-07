# LiteKey architecture

LiteKey is a Vietnamese input method for macOS (Apple Silicon), written entirely in Swift. It runs as a menu
bar app and works through a `CGEventTap`: it reads keystrokes, runs them through the typing engine and injects
the replacement text with synthetic key events.

## Goals

- The menu bar item, control panel and Vietnamese labels keep their familiar layout, with only the features
  people actually use.
- Typing output matches the fixtures in `Tests/fixtures/` character for character. The few rows where we
  intentionally differ are listed in `FixtureExceptions.swift` together with the reason.
- Event tap only: no Input Method Kit, no custom input source.
- Most of the code is plain Swift that builds and runs its tests on Linux. The macOS layer stays thin.
- No networking, no telemetry, no third-party dependencies.

## Modules

Dependencies only go one way: App → Platform → Core → Engine.

```
            ┌──────────────┐
            │ LiteKey (app)│  AppKit, SwiftUI
            └──────┬───────┘
                   ▼
          ┌─────────────────┐
          │ LiteKeyPlatform │  CoreGraphics, ApplicationServices, AppKit
          └────────┬────────┘
                   ▼
            ┌─────────────┐
            │ LiteKeyCore │  Pure Swift (Linux OK)
            └──────┬──────┘
                   ▼
           ┌───────────────┐
           │ LiteKeyEngine │  Pure Swift (Linux OK)
           └───────────────┘
```

| Target | Contents |
|---|---|
| `LiteKeyEngine` | Vietnamese typing state machine (`VietnameseEngine`), data tables, macro table. Input: key code, caps state, modifiers. Output: `EngineOutput` (backspaces, characters, restore key, empty-char suppression). |
| `LiteKeyCore` | `Preferences`, `Hotkey` + `HotkeyStateMachine`, `KeyEventProcessor` (one key in → pass/swallow + injection steps out), `InjectionPlanner` (`EngineOutput` + `AppContext` + `Preferences` → `[InjectionStep]`), `AppRules`, `SettleGate`, `PerAppLanguageStore`, `TapHealth`, `OtherInputMethods`, layout compatibility. |
| `LiteKeyPlatform` | `EventTap`, `EventNormalizer` (CGEvent → `KeyEvent`), `KeyboardPipeline`, `StepExecutor` (runs injection steps as CGEvents), `FocusProbe` (AX), monitors (permission, input source, Secure Input, other input methods), `LoginItem`, `Diagnostics`. |
| `LiteKey` (app) | `main`, `AppDelegate` (composition root), menu bar, control panel (SwiftUI), permission window, `PreferencesStore`. |

`Package.swift` declares `LiteKeyPlatform` and the app only under `#if os(macOS)`, so
`swift test --filter "LiteKeyEngineTests|LiteKeyCoreTests"` builds and runs on Linux.

## Design rules

- Decisions (key handling, hotkeys, injection strategy, per-app mode) are plain Swift functions and types. The
  macOS layer reads events, calls into Core and carries out the result.
- Structs and enums by default. No mutable globals and no singletons outside the app's composition root.
- Per-app behavior is data: bundle ID → rule in `AppRules`, not `if` checks spread around the code.
- Settings live in one `struct Preferences: Codable`, saved by a single UserDefaults store. Components get a copy
  when it changes.
- The tap callback has to return in under 1 ms, not counting the per-app delays we add on purpose. That means no
  extra allocations, no I/O, no UserDefaults and no `DispatchQueue.main.sync` in it. `EngineOutput` and
  `InjectionPlan` are reused between keys (`reset()` keeps capacity), which is why the planner and processor
  take `inout` parameters.
- Every event we post carries `EventMarker.value` in `eventSourceUserData`, so the tap can skip its own events.

## Key handling

1. `EventTap` runs on the main run loop and receives only key events (keyDown, keyUp, flagsChanged). Mouse clicks,
   which start a new word, are observed with a global `NSEvent` monitor, so a misbehaving tap can never block the
   mouse.
2. `EventNormalizer` turns the `CGEvent` into a plain `KeyEvent`.
3. `KeyEventProcessor` decides in this order: switch hotkey → mouse (new word, in every mode) → English mode /
   excluded app / non-English system input source → engine. Tapping ⌃ (spell checking off) or ⌘ (engine off)
   for the current word is also handled here. A change of app or system input source starts a new word.
   In Vietnamese mode, key repeats (a held key) other than Backspace pass untouched and start a new word, so
   holding a letter types it repeatedly instead of flipping its accent.
4. `InjectionPlanner` turns the engine output into steps using the cached `AppContext`.
5. `StepExecutor` posts the steps as marked CGEvents.

Mode changes from the hotkey take effect immediately inside the callback; the app is notified asynchronously
to persist preferences, update per-app memory and beep.

Everything the callback needs about the environment (frontmost app and its rule, Spotlight focus, system input
source, keyboard layout map, console session) is computed outside the callback and cached in `AppContext`.

### Injection strategy

- Autocomplete fix (on by default): before the backspaces, type an empty character (U+202F, or U+200C for
  Sublime Text) plus one extra backspace, so inline autocomplete in browsers and Electron apps cannot swallow
  the first backspace. Skipped in Spotlight, in terminals except Warp (no inline autocomplete there, so it only
  added a character, a backspace and 6 ms of pauses per key) and when the engine asks to suppress it.
- Chromium fix (opt-in): use Shift+← instead of the empty character in Chromium browsers (Chrome, Edge,
  Brave, Arc, Vivaldi, Opera, Chromium).
- Pass-through apps (`AppRule.passThrough`): remote desktop and VM clients and the iOS Simulator get every key
  untouched, like an excluded app, since the other side's own input method types Vietnamese. They stay out
  of smart switching too.
- Spotlight and other overlay launchers (Raycast, Alfred; `AppRules.isOverlayLauncher`): replace by selecting
  the old text (Shift+← × n) and typing over it. In Apple's Spotlight, confirmed by FocusProbe, send Forward
  Delete first: it removes an auto-selected inline suggestion, which would otherwise absorb the first
  Shift+←. Only while the caret is known to be at the end: any key other than typing (arrows, ⌃/⌘
  shortcuts, Tab, Esc, Return, a click) disables it until End, ⌘→, ⌘↓ or Spotlight opens again. Not in
  Raycast/Alfred, whose windows also host notes. Editing the field through AX instead would put AX calls in
  the callback.
- Send keys one by one (opt-in): one event per character instead of one string.
- Misspelled word ended by a control key: repost a copy of the original event, modifiers included.
- Macros: empty-char prefix when the autocomplete fix is on, unlimited backspaces (selection in Spotlight), the
  expansion, then the key that triggered it.
- Per-app delays: only terminals and JetBrains IDEs (`InjectionDelays.slow`); every other app gets
  back-to-back events. `SettleGate` makes the next real key wait only if it arrives before the app has had time
  to process the injected keys, so slow typing never waits. The pauses (3 ms per backspace, 6 ms before the
  text, 20 ms settle) are tuned for those apps: a replacement lands within about 10 ms, well under what
  typing feels as lag. Change them only with a QA run in those apps.
- Cost per key, measured once locally (release build, Apple Silicon, October 2026): about 0.2 µs for the
  decision path (`ProcessorPerformanceTests` prints it), versus a 1 ms budget.

### Focus probing

`FocusProbe` only asks AX for the PID of the focused element, to tell when Spotlight has focus. It never walks
the AX tree or reads roles: frequent AX queries can switch Chrome/Electron into accessibility mode and slow them
down. It re-probes after modifier+Space, and while Spotlight is open after ⌘+key, Esc, Enter, clicks and every
0.5 s. Until it answers, `KeyEventProcessor` assumes Spotlight for 0.5 s after a plain ⌘Space (ended early by
Esc, Enter, a click or a second ⌘Space) and only drops the empty char, so the first keys don't type it into
Spotlight. Plain backspaces work everywhere, so a wrong guess is harmless. A transient AX error while an
overlay is open keeps the last answer instead of reporting it closed.

### Layout compatibility and input source

The key remapping table for non-US layouts is precomputed with `UCKeyTranslate` whenever the input source
changes (`InputSourceMonitor`, on the main thread); the callback only indexes an array. The "disable Vietnamese
when the system input source is not English" check also reads a cached value.

## Reliability

- Permission loss: `PermissionMonitor` checks `AXIsProcessTrusted()` every 0.5 s on a background
  queue and disables the tap immediately when the permission is gone. When macOS disables the tap and the
  permission is missing, the callback disables it right away and the main thread removes it.
- Re-enabling the tap: while trusted, a tap disabled by macOS (timeout, user input, Secure Input) is
  re-enabled and the engine starts a new word. `TapDisableGuard` drops the tap only if it is disabled 5 times
  within 2 s, then retries after 1 s / 3 s / 10 s / 30 s; the counter resets after a minute of stable operation.
- Watchdog: every 5 s `TapHealth.check` re-enables a disabled tap or removes it if the permission is gone.
- Wake, unlock, Fast User Switching: start a new word, run the watchdog and re-probe focus. While the session
  is not on the console every event passes through untouched.
- Secure Input: `SecureInputMonitor` polls `IsSecureEventInputEnabled()` every 2 s and on focus changes; the
  menu bar icon and menu show which app holds it.
- Other input methods: `OtherInputMethodMonitor` warns (icon `V⚠︎`, menu line, error log) when another
  Vietnamese input method is running, since two input methods processing the same keys corrupt text.
- One copy at a time: at launch, before the tap starts, LiteKey asks older running copies of itself (same
  bundle ID, for example an old build in another folder) to quit, so the newest build keeps running
  (`SingleInstance`, `OlderCopies`).
- Hotkey: a switch hotkey has at least two keys, so at least one modifier (`Hotkey.isUsable`), whatever the
  source of the configuration. A bare letter can never be swallowed, and a lone ⌃ or ⌘ stays free for the
  "release alone" toggles. The control panel cannot go below two keys. Modifier-only hotkeys and the ⌃/⌘
  release toggles fire only on a tap: released within 0.5 s, with no click while held. A gesture
  spoiled by a key typed with ⌃ ⌥ ⌘ held, a click or an extra modifier fires nothing until every modifier
  is up, and the ⌃/⌘ toggles need ⌃ or ⌘ alone. While the system input source turns Vietnamese off, the
  hotkey is ignored and its key passes through.
- Smart switching ignores excluded apps: they neither restore nor record a mode.
- Once FocusProbe confirms an overlay launcher has focus, exclusion follows the launcher, not the app under
  it: Spotlight opened over an excluded app types Vietnamese, an excluded Raycast stays English. The first
  keys right after ⌘Space, before FocusProbe answers, still follow the app under it.
- Pass-through apps show no ✓ in the menu's "Loại trừ" item: that item only lists the user's own choices.
- Text events never split a surrogate pair at the 16-unit boundary, so emoji in macros arrive whole.

## Typing engine

`VietnameseEngine` is the typing state machine. A few odd-looking things are there on purpose, to keep the
output identical to the fixtures: loop counters shared between functions are stored properties, byte-sized
variables are `UInt8` and truncate, and out-of-range reads return 0. Static lookup tables are built when the
engine is created so the first key doesn't allocate them in the callback. Word history lives in one flat
`TypingHistory` buffer and the per-word arrays are cleared with `keepingCapacity`, so steady-state typing makes
no heap allocations in an optimized build (`AllocationTests`).

### Where the engine differs from the fixtures

| Change | Reason |
|---|---|
| Spelling restore is skipped for a word recovered by backspacing across a space when its key history is incomplete (`_keyStatesIncomplete`). | Restoring would delete the whole word but retype only the keys typed afterwards ("sa" + `pace` → "pace "). 48 rows of `editing.tsv` are affected and listed in `FixtureExceptions.swift`. |
| A new session (click, app switch, mode switch) right after a misspelled word starts a fresh word. | Otherwise the next word could not receive tone marks ("baanfk", click, "as" → "as"). |
| Word history keeps at most 128 entries. | Without Enter/Tab/arrows/clicks the history grew without bound and could reallocate inside the callback. |
| Quick start/end consonants are skipped for words of 30+ characters. | The 32-slot buffer overflowed and emitted garbage characters. |
| `MacroTable.openKeyData` skips entries whose shortcut exceeds 255 bytes or content exceeds 65,535 bytes. | The binary format cannot encode those lengths; writing them corrupts every entry that follows. |
| Macro files: a trailing `\r` is stripped from each line. | UniKey files written on Windows use CRLF. |
| A circumflex on "ươ" ("nguwowio") also redraws the ư that lost its horn. A standalone ư is not redrawn. | The screen showed "ngưôi" while the buffer held "nguôi". No fixture row changes. |
| A second `w` on iơ, oă and thuơ undoes the horn ("hoaww" → "hoaw"). | The key was swallowed and "hoă" stayed. No fixture row changes. |
| With "capitalize the first letter of a sentence" on, `!` and `?` end a sentence like `.`. | "xin chào! ban" kept a lowercase letter. No fixture row types `!` or `?` with the option on. |

Macros: `MacroTable` supports adding/editing/removing, the UniKey-compatible text file format and the
binary `macroData` format used for importing (byte for byte). LiteKey itself stores macros as JSON in UserDefaults (`Macros` key).

## Preferences

`Preferences` is stored as JSON under the `Preferences` key and carries a format `version`; `migrated()` upgrades
older configurations (for example, an untouched old default hotkey becomes the current default ⌃⇧). Defaults:
spelling restore on, autocomplete fix on, smart per-app switching on, disable Vietnamese for non-English input
sources on. "Restore defaults" keeps the current Vietnamese/English mode and the excluded app list.

"Import settings from OpenKey" reads the `com.tuyenmai.openkey` domain with `CFPreferencesCopyAppValue`
(input type, hotkey from `SwitchKeyStatus`, options and `macroData`). The per-app mode table (`smartSwitchKey`)
is not imported.

## Build and tooling

- SwiftPM + `build.sh` is the primary build. `project.yml` (XcodeGen) exists for debugging in Xcode;
  `*.xcodeproj` is not committed. The Xcode app target compiles only `Sources/LiteKey` (module `LiteKeyApp`) and
  links the package products, because Xcode cannot bundle a SwiftPM executable product.
- `Resources/Info.plist` uses Xcode variable syntax; `build.sh` substitutes the values with `sed`.
- CI (`.github/workflows/ci.yml`): `linux-swift-tests` (Swift 6.0 container), `macos-build` (Xcode 16: tests,
  release build, `.app` packaging and check, XcodeGen + unsigned `xcodebuild`) and `macos-latest-xcode`
  (latest stable Xcode on the `xcode-27` image; produces the `LiteKey.app.zip` artifact with Liquid Glass, which
  requires the macOS 26+ SDK and is gated by `#if compiler(>=6.2)`).
- UI snapshots (`.github/workflows/ui-snapshots.yml`): screenshots and click checks of the control panel and
  menu on macOS 27 and 15, from the debug-only `UISnapshot` (see [BUILDING.md](BUILDING.md#ui-snapshots-no-mac-needed)).
- Releases (`.github/workflows/release.yml`) build on `xcode-27`, ad-hoc signed.
- `./scripts/line_counts.sh` prints line counts per target.

## Testing

- `LiteKeyEngineTests` replays every file in `Tests/fixtures/` in name order through a single engine instance
  (state carries across rows and files, as in real typing), plus macro, restore and performance tests.
  `AllocationTests` (macOS) counts heap allocations while typing; it only runs in an optimized build:
  `swift test -c release -Xswiftc -enable-testing --filter AllocationTests`. CI runs it with Xcode 16
  (`macos-build`) and the latest Xcode (`macos-latest-xcode`).
- `LiteKeyCoreTests` covers the processor, planner, hotkeys, preferences migration, settle gate, tap health and
  an end-to-end path (processor → engine → planner → simulated screen).
- `Tests/fixtures/*.tsv` and `macros.txt` are reference data and cannot be regenerated. They are never
  edited; behavior changes go into the Swift engine with a test.
- Real-world typing is verified manually on a Mac with [QA.md](QA.md).
