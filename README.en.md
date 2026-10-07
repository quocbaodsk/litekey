<p align="center">
  <img src="docs/images/icon.png" width="128" alt="LiteKey icon">
</p>

<h1 align="center">LiteKey</h1>

<p align="center">
  Vietnamese input method for macOS.<br>
  Free, open source, no data collection.
</p>

<p align="center">
  <img alt="Status: Beta" src="https://img.shields.io/badge/status-beta-orange">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-555">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-100%25-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: GPL v3" src="https://img.shields.io/badge/license-GPL--3.0-blue"></a>
</p>

<p align="center">
  <a href="https://github.com/quocbaodsk/litekey/releases"><b>Download</b></a>
  &nbsp;·&nbsp; <a href="#installation">Installation</a>
  &nbsp;·&nbsp; <a href="#faq">FAQ</a>
  &nbsp;·&nbsp; <a href="docs/BUILDING.md">Building from source</a>
</p>

<p align="center">
  <a href="README.md">Tiếng Việt</a> &nbsp;·&nbsp; <b>English</b>
</p>

---

> [!IMPORTANT]
> LiteKey is in beta. It's a personal project that I use every day and share in case it's useful to
> someone else. Expect bugs and changes between releases.
> Bug reports are welcome in [Issues](https://github.com/quocbaodsk/litekey/issues).

## Overview

LiteKey is a menu bar input method for typing Vietnamese on macOS, written in Swift. The typing engine is
tested against more than 10,000 recorded key sequences, and each key is handled in well under a
millisecond, so fast typing in browsers, VS Code, Slack or Terminal doesn't lose letters. It never touches
the network.

<p align="center">
  <img src="docs/images/control-panel.png" width="560" alt="LiteKey control panel, typing options tab">
</p>

<p align="center">
  <img src="docs/images/tab-info.png" width="560" alt="LiteKey control panel, info tab">
</p>

## Features

### Typing

- Telex, VNI, Simple Telex 1 and 2
- Old-style (òa, úy) or new-style (oà, uý) tone placement, free tone marking
- Spell checking with automatic restore of English words: typing `class` stays `class`
- Quick Telex (cc → ch, gg → gi…), quick start/end consonants, auto-capitalize the first letter of a sentence

### Macros

- Personal macro table, with capitalization following how you type the shortcut
- Works in English mode too
- Import and export files compatible with UniKey and OpenKey

### Per app

- Remembers Vietnamese/English mode per app
- List of apps that always type English
- Pauses automatically when you switch to another system input source

### Other

- Switch Vietnamese/English with ⌃⇧, ⌥Z, ⌃⌥ or ⌃Space; ⌥-click the menu bar icon to toggle
- Tap ⌃ to turn spell checking off for the current word, or ⌘ to turn LiteKey off for it
- Warns when a password field holds the keyboard (Secure Input) or another Vietnamese input method is running
- Launch at login, optional Dock icon

## Requirements

- macOS 13 Ventura or later
- Apple Silicon Mac (M1 or later)
- Accessibility permission, to read and replace keystrokes

## Installation

1. Download the latest build from [Releases](https://github.com/quocbaodsk/litekey/releases), unzip it and
   drag **LiteKey** into **Applications**. No suitable release? See [Building from source](docs/BUILDING.md).
2. Open LiteKey and enable it in **System Settings → Privacy & Security → Accessibility**.
3. A **V** icon appears in the menu bar. Press and release **⌃⇧** to switch between Vietnamese and English.

Coming from OpenKey? Import your settings and macros from LiteKey's control panel, then quit OpenKey so the
two don't both handle the same keys.

## Privacy

LiteKey needs the Accessibility permission to read keystrokes and replace them with accented text; every
event-tap based input method on macOS does. There is no networking code and no analytics, nothing you type
is stored, and settings stay in UserDefaults on your Mac.

## FAQ

<details>
<summary><b>No tone marks, or letters go missing?</b></summary>

Make sure the macOS input source (top right of the menu bar) is **ABC** and no other Vietnamese input method is
running. If one is, LiteKey shows ⚠︎ on its icon and names the input method to quit.

</details>

<details>
<summary><b>macOS says the app cannot be opened?</b></summary>

Go to **System Settings → Privacy & Security** and click **Open Anyway** next to the LiteKey message.

</details>

<details>
<summary><b>Accessibility is granted but typing still does not work?</b></summary>

After an update macOS sometimes keeps the permission bound to the old build. Remove LiteKey from the
Accessibility list with **−**, reopen LiteKey and grant the permission again.

</details>

<details>
<summary><b>How do I uninstall LiteKey?</b></summary>

Quit LiteKey from its menu, delete the app from Applications, then remove it from the Accessibility list.

</details>

## Contributing

When reporting a bug, include your macOS version, the app you were typing in, the keys you pressed, and what
you expected versus what you got.

To build and run the tests see [docs/BUILDING.md](docs/BUILDING.md); the design is described in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Please open an issue before starting on anything large.

## Project layout

Dependencies only go one way: LiteKey (app) → LiteKeyPlatform → LiteKeyCore → LiteKeyEngine. Engine and Core
are pure Swift and tested on Linux; Platform is a thin macOS layer.

```
Sources/
  LiteKeyEngine/       Typing engine (Telex/VNI, spelling, macros)
  LiteKeyCore/         Pure logic
    Input/             Key events, key processing, switch hotkey, layout compatibility
    Injection/         Injection plans, per-app rules, settle gate
    Preferences/       Preferences, OpenKey settings import, per-app mode memory
    System/            Event tap health, detection of other input methods
  LiteKeyPlatform/     Thin macOS layer
    EventTap/          Event tap, event normalization, pipeline, key injection
    Monitors/          Permission, input source, other input methods, Secure Input
    System/            Focus probe (AX), launch at login, diagnostics
  LiteKey/             App: main.swift, AppDelegate (composition root)
    MenuBar/           Menu bar item
    ControlPanel/      Control panel, macro editor
    Permission/        Accessibility permission window
    Preferences/       Preferences persistence (UserDefaults)
Tests/
  LiteKeyEngineTests/  Engine tests, including the fixtures in Tests/fixtures
  LiteKeyCoreTests/    Pure logic tests
  fixtures/            Expected typing output (do not edit)
Resources/             Info.plist, icons
scripts/               CI helpers (app bundle check, xcodebuild), line counts
docs/                  Architecture, building, QA checklist, landing page
```

## License

LiteKey is released under the [GNU GPL v3](LICENSE). See [CREDITS.md](CREDITS.md) for acknowledgements.
