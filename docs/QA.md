# Manual QA checklist

Things CI can't check: run these on a real Mac before a release, or after touching key handling, injection or
the UI.

Grab the build from the PR's CI run: job `macos-latest-xcode` → Artifacts → `LiteKey.app.zip`. That one is built
with the latest Xcode and has Liquid Glass; the `macos-build` job uses Xcode 16 and doesn't.

Quit OpenKey, XKey, EVKey and any macOS Vietnamese input source first. Two input methods at once will mangle text.

When something fails, write down the app, its bundle ID (`osascript -e 'id of app "Name"'`), the keys you typed
and what came out, and attach a diagnostic log (use your own bundle ID instead of `com.litekey.app` if you
built with `BUNDLE_ID`):

```bash
defaults write com.litekey.app DebugLogging -bool YES     # then quit and reopen LiteKey
# ... reproduce ...
log show --predicate 'subsystem == "com.litekey.app"' --last 10m --info > ~/Desktop/litekey.log
defaults delete com.litekey.app DebugLogging               # the log contains typed text
```

Each key gets one line: event, key code, pass/swallow, `bs=` (backspaces), `text=`, `vi=` (Vietnamese mode),
`inputEN=` (English input source), app, Spotlight, processing time, sleep and settle wait. A `SLOW` line means the
callback took over 1 ms. Tap disable/re-enable is logged even with diagnostics off.

macOS treats every ad-hoc rebuild as a new app. If nothing gets accented while the menu shows V, run
`tccutil reset Accessibility com.litekey.app` (or remove LiteKey from the Accessibility list), reopen LiteKey and
grant the permission again.

## Basic typing

| # | Action | Expected |
|---|---|---|
| T1 | TextEdit: `Tooi ddang gox tieesng Vieejt, thuwr nghieejm: class string window.` | `Tôi đang gõ tiếng Việt, thử nghiệm: class string window.` |
| T2 | Type T1 very fast, several times | No lost or self-deleted letters; no tap-disabled lines in the log |
| T3 | `tieengs<<ng` (`<` = Delete) | `tiếng` |
| T4 | Fast: `tooi ddang thuwr gox trong laf laf as` in VS Code, Chrome, Safari, TextEdit, Slack | `tôi đang thử gõ trong là là á` |
| T5 | `sapce maf`, Delete ×6, `pace`, Space | `sâpce ` |
| T6 | Accented word, Space, next word, Delete back into the previous word, add letters, Space | No letters of the previous word are lost |
| T7 | `baanfk`, click elsewhere in the same field, `as` | `á` |
| T8 | As T7, replacing the click with ⌘Tab away and back, and with the switch hotkey pressed twice | `á` |
| T9 | Click into the middle of a word being typed, keep typing | A new word starts |
| T10 | Input types VNI / Simple Telex 1 / 2: `tie61ng vie65t` (VNI) | `tiếng việt` |
| T11 | Quick Telex on: `ccaf` | `chà` |
| T12 | Quick consonants on, spell checking off: `fas `, `cag ` | `phá `, `cang ` |
| T13 | Auto-capitalize on: `xin chaof. toio`, `xin chaof! toio`, `xin chaof? toio` | First letter of each sentence capitalized |
| T14 | "Temporarily disable spell checking with ⌃" on: `thuowng`, press and release ⌃, keep typing | Spell checking is off for the rest of the word |
| T15 | "Temporarily disable LiteKey with ⌘" on: press and release ⌘, type `aa ` | `aa ` |
| T16 | Dvorak layout + layout compatibility on: type `tieengs` by Dvorak labels | `tiếng` |
| T17 | Switch the system input source to Japanese/Pinyin and type | LiteKey does not interfere |

## Apps

| # | App | Action | Expected |
|---|---|---|---|
| A1 | Chrome/Safari/Arc address bar | `vnexpress`, `tieengs vieetj` while suggestions show | No letters eaten by autocomplete, no extra characters |
| A1b | Firefox (also LibreWolf, Zen if installed): address bar while suggestions show, then a search field and a text area inside a page | Fast: `tieengs vieetj`, `ddi hocj`, `dichj` | `tiếng việt`, `đi học`, `dịch` everywhere; no eaten or doubled letters (`diịch`, `goõ`), no visible empty char |
| A2 | Chrome address bar, Chromium fix on | `tieengs vieetj` | `tiếng việt` |
| A3 | Chrome search field and address bar | Fast: `tooi ddax awn cows chuwa ` | `tôi đã ăn cơm chưa `, spaces intact |
| A4 | Google Docs, Google Sheets | T1 | No lost or doubled letters |
| A5 | Slack / Discord / Messenger / Zalo | `guwir`, `suwar`, `maats`; send a message with Enter and immediately type `tooi laf ` | `gửi`, `sửa`, `mất`; `tôi là ` |
| A6 | Terminal, iTerm2, Ghostty (also Rio, Termius; Warp keeps the empty char, check it the same way) | Fast `echo tieengs Vieejt`, then ⌃C; also with zsh/fish autosuggestions on | Correct text, no stray characters; ⌃C interrupts; log shows `bs=1` steps without the empty char and non-zero `settle=` when typing fast |
| A7 | VS Code / Cursor | Type in a comment and in the search field | Correct text |
| A8 | Spotlight (⌘Space) | Wait ~0.5 s, type `tieengs vieetj`; Esc; type the same in TextEdit | Both correct |
| A9 | Spotlight | Type `tieengs` immediately after ⌘Space | `tiếng`, first keys included |
| A9b | Spotlight, inline suggestion showing | Fast: `maf` (Mail gets suggested), `tieengs`; a macro shortcut | `mà`, `tiếng`; macro fully replaced, no leftover letter |
| A9c | Spotlight | Type `vieet`, press ← twice (also try ⌃A, ↑), type `aa` | Letters after the caret are not deleted |
| A9d | ⌘Space bound to something else (Spotlight shortcut off) | ⌘Space, then immediately type `tieengs` in TextEdit, Terminal and Chrome's address bar | `tiếng` everywhere |
| A10 | Raycast / Alfred | `tieengs vieetj`, fast; also in a Raycast note with the caret mid-text | `tiếng việt`, no stray space-like character, no letter deleted after the caret |
| A11 | Excel / Numbers, column already containing "Việt" | `Vieejt Nam` | Autocomplete does not interfere |
| A12 | Sublime Text | `tieengs` | `tiếng` |
| A13 | "Send keys one by one" on | T1 in TextEdit and Chrome | Same as T1 |
| A14 | Password fields | A password containing `aa`, `dd` | Password accepted unchanged |
| A15 | Chrome, VS Code, Slack with many Enter and ⌘C/⌘V | Type fast | No stutter, no lost letters |
| A16 | Edge (stable), Arc, Brave with the Chromium fix on | `tieengs vieetj` in the address bar | `tiếng việt` |
| A17 | Microsoft Remote Desktop / Jump / Parallels / iOS Simulator | Type `tieengs` | Letters arrive untouched (`tieengs`); the remote side's own input method decides |
| A18 | TextEdit | Hold `o` for a second, then type `s`; hold Backspace over `tiếng`, then type `as` | `oooo…s`, no flicker between `ô` and `oo`; `á` after the deletion |
| A19 | Spotlight over an excluded Terminal | Type `tieengs`; Esc, type the same in Terminal | Spotlight `tiếng`; Terminal `tieengs` |
| A20 | Spotlight, Raycast, Alfred, AX edit (default) with `DebugLogging` on | Repeat A8, A9b, A9c and A10; type `thuwj nghieejm gox nhanh` as fast as you can | Same results, `thực nghiệm gõ nhanh`; log shows `AX edit replaced in …ms` with `keyWaited=` near 0 when typing at normal speed; no `failed` or `ran past its time limit` lines |
| A21 | Spotlight while it is still searching (type right after ⌘Space, long query) | `tieengs vieetj nam` | Correct text; any `failed, used key events` line is followed by correct output |
| A22 | Spotlight, Raycast note, AX edit | `vieetj`, then ⌘Z | Undo behaves acceptably (note whether it undoes one letter, the word or the whole query) |
| A22b | Raycast note, caret mid-text | Type `vieetj` between two existing words | `việt`, nothing after the caret deleted |
| A22c | Raycast, Alfred search fields | `tieengs`, `dduwowcj`, `thuwr` | No doubled word (`tiếngtiếng`) and no leftover letters; log shows `replaced`, not `failed` |
| A23 | Compare | Hệ thống → turn off "Sửa lỗi Spotlight, Raycast, Alfred", repeat A20 without relaunching; turn it back on | Off: no `AX edit` lines, behaves as 1.0.1. Note which feels better and any difference in output |

## Macros

| # | Action | Expected |
|---|---|---|
| M1 | Menu → Gõ tắt...: add `vn` → `Việt Nam` (type it with Telex in the field) | Entry appears; the button becomes "Sửa" when `vn` is typed again |
| M2 | Vietnamese mode, TextEdit: `vn `, `vn.`, `vn,`, `tooi owr vn ` | `Việt Nam `, `Việt Nam.`, `Việt Nam,`, `tôi ở Việt Nam ` |
| M3 | Auto-capitalize macros on: `Vn `, `VN ` | `Việt Nam `, `VIỆT NAM ` |
| M4 | English mode, "macros in English mode" on: `vn ` | `Việt Nam ` |
| M5 | Macros off: `vn ` | `vn ` |
| M6 | Load from file (UniKey/OpenKey .txt), answer Có / Không | Có: merged; Không: replaced |
| M7 | Export to file, open in UniKey/OpenKey | Readable |
| M8 | Macros in the Chrome address bar, Slack, Terminal | No lost or extra characters |
| M9 | Macro with emoji (`:)` → `😀`) | Correct emoji |
| M9a | Macro whose content is 15 letters then an emoji (`aaaaaaaaaaaaaaa😀`) | Emoji intact, no `�` |
| M10 | English mode, macros in English mode on: type `vn`, click elsewhere in the text, press Space | Plain space, nothing deleted |

## Menu bar and control panel

| # | Action | Expected |
|---|---|---|
| U1 | Click the menu bar icon | Menu: Bật Tiếng Việt (hotkey) / Kiểu gõ ▸ / Loại trừ “app” / Ứng dụng loại trừ ▸ / Bảng điều khiển... / Gõ tắt... / Giới thiệu / Thoát |
| U2 | ⌥-click the icon | Toggles Vietnamese without opening the menu |
| U3 | Light/dark mode, modern menu bar icon on/off | Icon legible in both; off shows V/E |
| U4 | Switch apps with smart switching on, open the menu | Icon and menu match each app's mode |
| U5 | Control panel, every sidebar page, light and dark | Labels intact, no truncated or clipped text (long labels wrap); cards and controls share the same left and right edges (segmented pickers and "Kêu beep" end where the switches end); two-column options have no empty cell; the window does not resize when switching pages; a page that fits does not bounce when scrolled (macOS 13.3+); the sidebar shows "Cài đặt" (Bộ gõ, Gõ tắt, Hệ thống) and "Hỗ trợ" (Báo lỗi, Thông tin) headings; Báo lỗi shows the "Sắp ra mắt" placeholder |
| U6 | macOS 26+: control panel and permission window | Sidebar is a floating glass panel with the traffic lights on it, its selection slides between pages; buttons, ⌃ ⌥ ⌘ ⇧ keys and status pill use glass (checked keys tinted); Đóng is the prominent button; the page and its title cross-fade together; Kiểu gõ and Chế độ gõ show a glass pill that slides to the clicked segment, and pressing then dragging sideways moves it segment by segment (macOS 13–15: native segmented picker); with Full Keyboard Access on, Tab reaches them and ←/→ change the choice; VoiceOver reads each segment and can adjust it |
| U7 | macOS 13–15 | Classic appearance (full-height sidebar material with a divider), no glitches |
| U8 | Hotkey field: click it, hold ⌃, press Space | Hotkey becomes ⌃Space, only ⌃ on; keys are not transformed while recording |
| U9 | Hotkey ⌃⇧ + key: press Delete in the field. Then hotkey ⌥Z: press Delete | First: key removed, ⌃⇧ left. Second: beep, ⌥Z kept |
| U10 | Hotkey ⌥Z: try to turn off ⌥ | Not allowed; typing `z` works normally |
| U11 | Hotkey ⌃⇧: try to turn off ⌃ or ⇧ | Not allowed, the hotkey always keeps two keys |
| U12 | Open LiteKey (control panel shows), click nothing, type `tieengs Vieejt` in TextEdit | `tiếng Việt` |
| U13 | Click the hotkey field, switch to another app without pressing keys, type `as` | `á` (recording stops when the window loses focus) |
| U14 | Mặc định → Có | Defaults restored; Vietnamese/English mode and excluded apps kept |
| U15 | Kết thúc / Đóng (or Return) | Quits / closes the window |
| U16 | "Bật bảng này khi khởi động", "Hiện biểu tượng trên thanh Dock" | Panel opens at launch; Dock icon present and opens the panel |
| U17 | Excluded apps: add/remove an app | Each app is listed with its icon; listed apps always type English |
| U17a | In Safari, menu → Loại trừ “Safari” | Checked; Safari types English right away; the item shows ✓ next time |
| U17b | Menu → Ứng dụng loại trừ ▸ → click Safari | Removed; Safari types Vietnamese again |
| U17c | Menu → Ứng dụng loại trừ ▸ → Quản lý... | Control panel opens on Hệ thống with the excluded apps list |
| U18 | Import settings from OpenKey (Mac with OpenKey and macros) | Input type, hotkey, options and macros imported |
| U19 | "Khởi động cùng macOS" | Can be enabled (may fail on ad-hoc builds; note it) |
| U20 | Switch modes in TextEdit, go to Notes, come back | Each app keeps its own mode (smart switching on) |
| U21 | Hotkey ⌃⇧: hold ⌃⇧ ~1 s and release; hold ⌃⇧ and click; ⌃⇧ quick tap | Only the quick tap toggles |
| U22 | "Tạm tắt LiteKey bằng phím ⌘" on: ⌘-click a link, then type `as` | `á` (⌘-click does not turn the engine off) |
| U23 | Smart switching on, Terminal excluded: Vietnamese in TextEdit, switch to Terminal, toggle the hotkey there, back to TextEdit | TextEdit is still Vietnamese |
| U24 | TextEdit: type `vieet`, switch to Japanese input (or ABC ↔ another source) and type, switch back, type `j` | No old letters deleted |
| U25 | Hotkey ⌃⇧: press ⌃⇧⌥ then release ⌥, ⇧, ⌃ one by one; also ⌃⇧A (some shortcut) releasing ⇧ before ⌃ | No toggle, no temporary spell-check off |
| U26 | Japanese input source active, "Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh" on: press the hotkey | Menu icon does not change |
| U27 | Hover, then click a "?" next to an option | Tooltip on hover; click opens a popover with the same text |
| U28 | Revoke Accessibility, open the control panel | Red banner with "Thử lại" on every page instead of the green status pill |
| U29 | Thông tin: click Trang chủ, Mã nguồn, GPL v3 | The browser opens litekey.quocbao.dev, the GitHub repository and the GPL v3 text |

## Permission and reliability

| # | Action | Expected |
|---|---|---|
| R1 | First launch without permission | Permission prompt; window "Bạn chưa cấp quyền cho ứng dụng hoạt động!"; menu shows ⚠︎; switches to V/E automatically once granted |
| R2 | Rebuild ad-hoc, launch while the old switch is still on | Window explains the switch belongs to the old build; "Đặt lại quyền" → grant → window closes, typing works |
| R3 | Launch straight from Downloads | Window asks to move the app to Applications if it runs translocated |
| R4 | While running, turn LiteKey off in Accessibility | Mouse always works; keyboard never freezes (at most ~1 s); menu shows ⚠︎ |
| R5 | While running, remove LiteKey from Accessibility with − (or `tccutil reset`) | As R4 |
| R6 | Grant the permission again after R4/R5 (without relaunching) | LiteKey resumes within seconds |
| R7 | Enter and leave several password fields in a row (Safari login, `sudo`), then type Vietnamese | Works immediately; no ⚠︎ |
| R8 | Focus a password field (Safari, Terminal Secure Keyboard Entry), open the menu | Lock on the icon, tooltip and menu line name the app; clears within ~2 s after leaving |
| R9 | Sleep (close the lid) and wake | Typing works immediately |
| R10 | Lock the screen (⌃⌘Q), unlock | Typing works; lock screen password unaffected |
| R11 | Fast User Switching to another user and back | Typing works; the other user is unaffected |
| R12 | Launch OpenKey (or XKey/EVKey) while LiteKey runs | Icon becomes `V⚠︎`, menu names the other input method; warning clears when it quits |
| R12b | With LiteKey running from /Applications, open a second copy from another folder (e.g. a fresh build in `build/`) | The first copy quits; typing `tieengs` gives `tiếng` (no doubled marks) |
| R13 | All-day use | Never needs a restart. Otherwise send `log show --predicate 'subsystem == "com.litekey.app"' --last 1h \| grep -i tap` |
| R14 | Debug build (`swift build`), type fast with logging on | No `SLOW` lines |

If R4/R5 ever freezes the keyboard: kill LiteKey from Activity Monitor (or `pkill -9 LiteKey` over SSH) and send
the log.

## Release

| # | Action | Expected |
|---|---|---|
| X1 | Actions → Release → Run workflow | Green on `xcode-27`; the zipped app has glass and opens after `xattr -dr com.apple.quarantine` |
