# LiteKey

Vietnamese input method for macOS on Apple Silicon. Read `docs/ARCHITECTURE.md` before any non-trivial change.

## Things that don't change without asking the owner

- The menu bar, control panel and Vietnamese labels keep their current layout and wording.
- Typing output matches `Tests/fixtures/` character for character.
- The architecture is our own: small, testable Swift.
- Event tap only (`CGEventTap`). No Input Method Kit, no custom input source.
- 100% Swift. The fixtures are reference data and can't be regenerated.

## Architecture

Dependencies only go one way: App → Platform → Core → Engine.

- `LiteKeyEngine` and `LiteKeyCore` are plain Swift with no AppKit, CoreGraphics or ApplicationServices, and their
  tests run on Linux.
- `LiteKeyPlatform` is the thin macOS layer: event tap, event normalization, key injection, AX, permissions.
- `LiteKey` is the app: composition root, menu bar, control panel.

New code follows the rules in `docs/ARCHITECTURE.md`: decisions live in plain Swift functions and types, structs
and enums by default, no mutable globals or singletons outside the composition root, per-app behavior as data in
`AppRules`, and one `Preferences` struct that components receive a copy of.

## Rules

- Never edit `Tests/fixtures/*.tsv`. Change the Swift engine instead, and list any row that intentionally differs
  in `FixtureExceptions.swift` with the reason.
- Any change to typing behavior comes with a test (fixtures, `LiteKeyEngineTests` or `LiteKeyCoreTests`).
- The event tap callback returns in under 1 ms, not counting the per-app delays we add on purpose. No extra
  allocations, network, file I/O, UserDefaults or `DispatchQueue.main.sync` inside it.
- Every event LiteKey posts carries `EventMarker.value` in `eventSourceUserData`.
- No third-party dependencies without asking. No data collection, nothing goes over the network.
- UI strings are Vietnamese and keep their current wording. Comments and docs are English, short and plain.
- References and attribution live in `CREDITS.md` (kept short), plus the one-line header of the ported engine
  file. A reference in code is fine when it fits in one short line at the spot that needs it; never sprinkle
  them. Docs, tests and commit messages describe LiteKey on its own terms. The project is GPL v3; code copied
  verbatim from another project needs that project's license included as is.

## Working without a Mac

Claude Code cloud runs Linux:

| What                                         | Where                                                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Engine and Core tests                        | In the container through Docker (below), and the `linux-swift-tests` CI job                                              |
| macOS build, Xcode project                   | GitHub Actions (`.github/workflows/ci.yml`); push and check CI                                                           |
| How the UI looks, clicks                     | `UI snapshots` workflow on macOS 27 and 15; `git fetch origin snapshots-xcode-27` and read the PNGs (`docs/BUILDING.md`) |
| Real typing (Chrome, Terminal, Spotlight...) | The owner, on a Mac, with `docs/QA.md`                                                                                   |

- Don't say the build succeeded until CI is green.
- There's no macOS compiler here, so double-check AppKit/CoreGraphics APIs against the SDK by hand.
- Every PR says what CI covered and what the owner still has to test by hand.

`download.swift.org` is blocked by the network policy but Docker Hub isn't. This works (Swift 6.0.3):

```bash
nohup dockerd > /tmp/dockerd.log 2>&1 &   # dockerd isn't started by default
docker pull swift:6.0-noble
# test on a copy so root-owned .build files don't end up in the repo
docker run --rm -v "$PWD":/src:ro swift:6.0-noble bash -c \
  'cp -r /src /tmp/w && cd /tmp/w && swift test --filter "LiteKeyEngineTests|LiteKeyCoreTests"'
```

If Docker doesn't work either, say so and rely on CI (`linux-swift-tests`, `macos-build`).

## Commands

```bash
swift test --filter "LiteKeyEngineTests|LiteKeyCoreTests"   # engine and core tests
swift build -c release --arch arm64   # macOS only
SIGN_ID=- ./build.sh                  # main build: packages the .app, ad-hoc signed (macOS only)
xcodegen && open LiteKey.xcodeproj    # optional, for debugging in Xcode (macOS only)
```

## Workflow

- One branch per change with small commits, then a PR that covers what changed, the CI result and what the
  owner needs to check by hand.
- Keep unrelated changes in separate PRs.
- Ask before changing a decision written down in `docs/ARCHITECTURE.md`. If a technical reason forces a different
  design, note the reason there in the same PR.
