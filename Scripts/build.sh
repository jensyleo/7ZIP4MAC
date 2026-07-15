#!/usr/bin/env bash
#
# build.sh — Generate the Xcode project, build the app, sign it (ad-hoc),
# and install it to /Applications as the single canonical copy.
#
# Usage:
#   Scripts/build.sh [--run]
#
# The app is installed to /Applications/7ZIP4MAC.app. To avoid the app being
# registered twice in Finder / "Open With", the DerivedData build product is
# unregistered from LaunchServices and no stray copy is left in build/.
#
# With --run the freshly installed app is (re)launched after building.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="7ZIP4MAC"
SCHEME="SevenZip4Mac"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
INSTALL_APP="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Generating Xcode project with xcodegen"
cd "$ROOT"
xcodegen generate

echo "==> Building ($SCHEME, Release)"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    build | tail -20

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "!! Build product not found at $BUILT_APP" >&2
    exit 1
fi

echo "==> Ad-hoc signing (inside-out): engine, then app"
# Nested code must be signed before the outer bundle so the outer signature is
# valid over it. Order: engine binary → app.
codesign --force --sign - "$BUILT_APP/Contents/Resources/Engine/7zz"
codesign --force --deep --sign - "$BUILT_APP"

echo "==> Installing to $INSTALL_APP"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3
# Remove any previous/stray copies and their LaunchServices registrations so
# the app never appears twice.
"$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
rm -rf "$BUILD_DIR/$APP_NAME.app"          # legacy dev copy, if present
rm -rf "$INSTALL_APP"
cp -R "$BUILT_APP" "$INSTALL_APP"
# Unregistering the DerivedData product isn't enough on its own: macOS's
# background LaunchServices/Spotlight scanning periodically rediscovers and
# re-registers *any* .app bundle it finds on disk, regardless of a prior
# `-u` call — which silently turns it back into an alternate handler for
# every format this app is associated with (confirmed: this is what made
# file associations survive pointing at a stray dev build after a real
# uninstall). The only reliable fix is to not leave a second real .app
# bundle on disk at all.
"$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
rm -rf "$DERIVED/Build/Products/Release/$APP_NAME.app"
"$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true

echo "==> Verifying signature"
codesign --verify --verbose=2 "$INSTALL_APP" 2>&1 || true

echo "==> Done: $INSTALL_APP"

if [[ "${1:-}" == "--run" ]]; then
    echo "==> Relaunching"
    open "$INSTALL_APP"
fi
