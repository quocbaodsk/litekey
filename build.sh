#!/usr/bin/env bash
# Build LiteKey.app for Apple Silicon.
#   ./build.sh             build into ./build/LiteKey.app
#   ./build.sh --install   build, copy into /Applications and relaunch
#   ./build.sh --notarize  build, sign with Developer ID, notarize with Apple, then staple (for release)
#   ./build.sh --help      show this help
#
# Environment variables:
#   BUNDLE_ID       (default com.litekey.app) -> change to your own, e.g. com.yourname.litekey
#   SIGN_ID         signing identity. Defaults to the first "Developer ID Application", then
#                   "Apple Development"; falls back to ad-hoc. SIGN_ID=- forces ad-hoc signing.
#   NOTARY_PROFILE  (default litekey) notarytool profile saved via `xcrun notarytool store-credentials`
#   VERSION         (default 1.0.1)
#   ARCH            (default arm64; use "arm64 x86_64" for a universal build)
#
# Exit codes: 0 success, 1 build/sign/notarize failure, 2 invalid usage or environment.
set -euo pipefail
cd -- "$(dirname -- "$0")"

APP_NAME="LiteKey"
BUNDLE_ID="${BUNDLE_ID:-com.litekey.app}"
VERSION="${VERSION:-1.0.1}"
ARCH="${ARCH:-arm64}"
OUT="build/${APP_NAME}.app"
DEV_ID_PREFIX="Developer ID Application"

usage() { sed -n '2,16s/^# \{0,1\}//p' "$0"; }
die() { printf '!!  %s\n' "$1" >&2; exit "${2:-1}"; }
step() { printf '==> %s\n' "$1"; }

DO_INSTALL=0
DO_NOTARIZE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --install) DO_INSTALL=1 ;;
    --notarize) DO_NOTARIZE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" 2 ;;
  esac
  shift
done

# Values are spliced into Info.plist via sed, so restrict them to safe characters.
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "Invalid BUNDLE_ID: $BUNDLE_ID" 2
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || die "Invalid VERSION (expected N[.N[.N]]): $VERSION" 2

# A full Xcode install is required: Command Line Tools lack the SwiftUI macro plugin (@State...)
# and fail with the cryptic "plugin for module 'SwiftUIMacros' not found".
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
case "$DEV_DIR" in
  ""|*CommandLineTools*)
    cat >&2 <<EOF
!!  Using Command Line Tools (${DEV_DIR:-not found}); a full Xcode install is required.
    Install Xcode from the App Store, then run:
      sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
      sudo xcodebuild -license accept
    Or for this build only:
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build.sh
EOF
    exit 2
    ;;
esac

find_identity() {
  # A missing identity is an expected outcome, not an error.
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -F -- "\"$1" | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true
}

# Resolve the signing identity before building so --notarize fails fast.
SIGN_ID="${SIGN_ID:-}"
[ -n "$SIGN_ID" ] || SIGN_ID="$(find_identity "$DEV_ID_PREFIX")"
[ -n "$SIGN_ID" ] || SIGN_ID="$(find_identity 'Apple Development')"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="-"
  echo "!!  No Developer ID / Apple Development certificate found -> signing ad-hoc."
  echo "    Accessibility permission must be re-granted after every rebuild (see docs/BUILDING.md)."
fi

IS_DEV_ID=0
case "$SIGN_ID" in "$DEV_ID_PREFIX"*) IS_DEV_ID=1 ;; esac
if [ "$DO_NOTARIZE" -eq 1 ] && [ "$IS_DEV_ID" -eq 0 ]; then
  die "Notarization requires a $DEV_ID_PREFIX certificate (current identity: $SIGN_ID)" 2
fi

ARCH_FLAGS=()
for a in $ARCH; do ARCH_FLAGS+=(--arch "$a"); done # split intended
[ "${#ARCH_FLAGS[@]}" -gt 0 ] || die "ARCH must not be empty" 2

step "swift build ($ARCH)"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

step "Packaging $OUT"
rm -rf -- "$OUT"
mkdir -p -- "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp -- "$BIN_DIR/$APP_NAME" "$OUT/Contents/MacOS/$APP_NAME"
cp -- Resources/LiteKey.icns "$OUT/Contents/Resources/LiteKey.icns"
# Info.plist uses Xcode variable syntax (shared with project.yml); substitute them here.
PLIST="$OUT/Contents/Info.plist"
sed -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/'"$BUNDLE_ID"'/' \
    -e 's/\$(MARKETING_VERSION)/'"$VERSION"'/' \
    -e 's/\$(CURRENT_PROJECT_VERSION)/'"$VERSION"'/' \
    Resources/Info.plist > "$PLIST"
if grep -q '\$(' "$PLIST"; then
  grep '\$(' "$PLIST" >&2
  die "Info.plist still contains unresolved variables"
fi
plutil -lint -s "$PLIST"

SIGN_FLAGS=(--force --sign "$SIGN_ID" --identifier "$BUNDLE_ID")
# Release: hardened runtime + secure timestamp are prerequisites for notarization.
[ "$IS_DEV_ID" -eq 0 ] || SIGN_FLAGS+=(--options runtime --timestamp)
step "codesign ($SIGN_ID)"
codesign "${SIGN_FLAGS[@]}" -- "$OUT"
codesign --verify --strict --verbose=1 -- "$OUT"

if [ "$DO_NOTARIZE" -eq 1 ]; then
  PROFILE="${NOTARY_PROFILE:-litekey}"
  ZIP="build/${APP_NAME}-${VERSION}.zip"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf -- "$TMP_DIR" "$ZIP.partial"' EXIT

  step "Notarizing (profile $PROFILE)"
  ditto -c -k --keepParent "$OUT" "$TMP_DIR/upload.zip"
  xcrun notarytool submit "$TMP_DIR/upload.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$OUT"
  spctl --assess --type execute --verbose "$OUT"
  # Re-zip the stapled app for distribution; publish atomically so a failure never leaves a partial zip.
  # Staged inside build/ so mv stays on one volume (a rename, not copy+delete).
  ditto -c -k --keepParent "$OUT" "$ZIP.partial"
  mv -f -- "$ZIP.partial" "$ZIP"
  printf 'Release archive: %s\n' "$ZIP"
fi

if [ "$DO_INSTALL" -eq 1 ]; then
  DEST="/Applications/${APP_NAME}.app"
  step "Installing into /Applications"
  # Not running is fine; then wait up to ~5s for the old instance to exit before replacing it.
  pkill -x "$APP_NAME" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.5
  done
  pgrep -x "$APP_NAME" >/dev/null && die "$APP_NAME is still running; quit it and retry"
  rm -rf -- "$DEST"
  ditto "$OUT" "$DEST"
  open "$DEST"
fi

printf 'Done: %s\n' "$OUT"
