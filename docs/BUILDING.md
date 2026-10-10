# Building and developing LiteKey

For people building from source or contributing code. The product overview is in the [README](../README.en.md) ([Tiếng Việt](../README.md)).

## Building from source

You need the full Xcode, not just the Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
BUNDLE_ID=com.yourname.litekey ./build.sh --install   # build, install into /Applications and launch
```

To debug in Xcode: `brew install xcodegen && xcodegen && open LiteKey.xcodeproj` (the project is generated from
`project.yml`). To preset the signing team: `LITEKEY_TEAM=<Team ID> xcodegen`; without it the team is left empty.

## Code signing

macOS binds the Accessibility permission to the app's signature. `build.sh` picks a certificate in this order:

| Certificate | Use for | Notes |
|---|---|---|
| Developer ID Application | Distributing to others | Requires the Apple Developer Program. Signed with hardened runtime; can be notarized. |
| Apple Development | Personal use | Free. Keeps the Accessibility permission across rebuilds (keep `BUNDLE_ID` fixed). |
| Ad-hoc (`-`) | No certificate available | Accessibility must be re-granted after every rebuild. |

For personal use (free): Xcode → Settings → Accounts → sign in with your Apple ID → select the Personal Team →
Manage Certificates → `+` → Apple Development. Then run `./build.sh --install`.

For a release (Developer ID + notarization):

```bash
# 1. Create a "Developer ID Application" certificate in Xcode (Manage Certificates → + → Developer ID Application)
# 2. Store notarization credentials once (create an app-specific password at account.apple.com)
xcrun notarytool store-credentials litekey --apple-id "you@example.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"
# 3. Build, sign, notarize, staple
BUNDLE_ID=com.yourname.litekey VERSION=1.0.0 ./build.sh --notarize
```

The result is `build/LiteKey-<version>.zip`, which opens on other Macs without Gatekeeper warnings.
Pick a specific certificate with `SIGN_ID="Developer ID Application: Name (TEAMID)"` and another notary profile
with `NOTARY_PROFILE`.

## Development

```bash
swift test --filter "LiteKeyEngineTests|LiteKeyCoreTests"   # also runs on Linux
```

The design is described in [ARCHITECTURE.md](ARCHITECTURE.md) and the source tree in the
[README](../README.en.md#project-layout).

Apps that need a specific injection strategy (delays, empty-character prefix) are listed by bundle ID in
`Sources/LiteKeyCore/Injection/AppRules.swift`. Find an app's bundle ID with `osascript -e 'id of app "App Name"'`.

### UI snapshots (no Mac needed)

The `UI snapshots` workflow (`.github/workflows/ui-snapshots.yml`) runs on every push that touches
`Sources/LiteKey/` and can be started by hand. On macOS 27 (Liquid Glass) and macOS 15 it builds the debug app
and runs it with `LITEKEY_SNAPSHOT_DIR` set, which makes `Sources/LiteKey/Debug/UISnapshot.swift` take over
instead of the input method:

- screenshots of every control panel page (light and dark), disabled options, the hotkey warning, a page
  switch mid-animation, a hovered row, the macro window, the excluded apps list and the menu bar menu;
  `<name>.png` comes from the window server (glass included, 1x), `<name>-2x.png` is drawn from the view
  (no glass, so the macOS 26+ glass sidebar and anything on it are missing there);
- click checks with real mouse events (switch labels, the ⌥ key, a disabled option, a sidebar item) in `checks.txt`,
  and the menu items in `menu.txt`. The job fails on any `FAIL` line or if the run hangs.

Get the results from the run's artifacts, or with git (handy from a Linux container):

```bash
git fetch origin snapshots-xcode-27 && git show FETCH_HEAD:SOURCE      # commit and branch they were made from
mkdir -p /tmp/shots && git archive FETCH_HEAD | tar -x -C /tmp/shots
```

The click positions are measured on the macOS 27 screenshots; after a layout change, update them in
`UISnapshot.clickChecks()`. The code is under `#if DEBUG`, so release builds don't contain it. Run it locally
from the repo root with `swift build && LITEKEY_SNAPSHOT_DIR=/tmp/shots .build/debug/LiteKey`.

### Diagnostic logging

Off by default. When enabled, the log contains the text you type. The commands use the default bundle ID
`com.litekey.app`; use your own if you built with `BUNDLE_ID`.

```bash
defaults write com.litekey.app DebugLogging -bool YES       # then quit and reopen LiteKey
log show --predicate 'subsystem == "com.litekey.app"' --last 10m --info
defaults delete com.litekey.app DebugLogging
```

## License

GNU GPL v3, see [`LICENSE`](../LICENSE). Acknowledgements are in [`CREDITS.md`](../CREDITS.md).
