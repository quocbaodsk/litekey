# Removing LiteKey from a Mac

These commands remove everything LiteKey leaves on a Mac. They only touch paths named `LiteKey` or
`com.litekey.*`. The repo and its source code are not touched.

First, open the LiteKey control panel and turn off "Khởi động cùng macOS". Deleting the app alone can leave
the entry in System Settings → General → Login Items.

```bash
# 1. Quit LiteKey
osascript -e 'quit app "LiteKey"'

# 2. Settings (the app's own, and the one the UI snapshot run uses)
defaults delete com.litekey.app
defaults delete com.litekey.snapshot
rm -f ~/Library/Preferences/com.litekey.app.plist ~/Library/Preferences/com.litekey.snapshot.plist

# 3. Accessibility permission (LiteKey only)
tccutil reset Accessibility com.litekey.app

# 4. The installed app
rm -rf /Applications/LiteKey.app

# 5. Caches and saved window state (usually absent)
rm -rf ~/Library/Caches/com.litekey.app ~/Library/"Saved Application State"/com.litekey.app.savedState

# 6. Per-app cache folder macOS creates in /var/folders (Metal shader cache)
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.litekey.app"
```

- `defaults delete` prints "Domain ... not found" when there is nothing to delete. That's fine.
- Logs: LiteKey writes no log files. It logs to the macOS unified log (os_log), which can't be cleared per app.
  The `DebugLogging` switch lives in the settings and goes away in step 2.
- If you built with a custom `BUNDLE_ID`, use it instead of `com.litekey.app` in steps 2, 3, 5 and 6.
- Macro exports ("Xuất ra file..." in Gõ tắt) are saved where you chose. They are your files and are not removed.
- `defaults delete` goes through `cfprefsd`. Deleting only the `.plist` file isn't enough, because `cfprefsd`
  can write it back.

## Optional: build leftovers

Only there if you built from source. None of this is source code, and the build tools recreate it.

```bash
# Xcode build cache and Xcode's coding assistant data for the project
ls -d ~/Library/Developer/Xcode/DerivedData/LiteKey-*
ls -d ~/Library/Developer/Xcode/UserData/CodingAssistant/LiteKey-*
rm -rf ~/Library/Developer/Xcode/DerivedData/LiteKey-*
rm -rf ~/Library/Developer/Xcode/UserData/CodingAssistant/LiteKey-*

# SwiftPM lock files and Swift macro expansions in the temp folder (module name "LiteKey" is mangled as 7LiteKey)
rm -f "$TMPDIR"_Users_*_LiteKey_.build*.lock
rm -f "$TMPDIR"swift-generated-sources/@__swiftmacro_7LiteKey*
```

Any other project named exactly `LiteKey` also matches these patterns. Check the `ls` output before deleting.
In zsh, a pattern with no match is an error ("no matches found") and that line deletes nothing, so each
pattern is on its own line.
