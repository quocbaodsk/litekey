#!/bin/bash
# Validate the packaged LiteKey.app (used by CI).
set -euo pipefail
app="${1:-build/LiteKey.app}"
plist="$app/Contents/Info.plist"
plutil -lint "$plist"
if grep -q '\$(' "$plist"; then
  echo "Info.plist has unresolved variables:"; grep '\$(' "$plist"; exit 1
fi
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "${BUNDLE_ID:-com.litekey.app}"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$plist")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")" = "LiteKey.icns"
test -s "$app/Contents/Resources/LiteKey.icns"
test "$(lipo -archs "$app/Contents/MacOS/LiteKey")" = "arm64"
codesign --verify --verbose "$app"
echo "LiteKey.app OK"
