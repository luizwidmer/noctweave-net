#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ROOT="$PACKAGE_ROOT/dist/Noctweb Browser.app"
CONTENTS_ROOT="$APP_ROOT/Contents"
MACOS_ROOT="$CONTENTS_ROOT/MacOS"
RESOURCES_ROOT="$CONTENTS_ROOT/Resources"
SIGNING_IDENTITY="${NOCTWEB_BROWSER_CODESIGN_IDENTITY:--}"

swift build \
  --package-path "$PACKAGE_ROOT" \
  --configuration release \
  --product NoctwebBrowser

BIN_PATH="$(swift build \
  --package-path "$PACKAGE_ROOT" \
  --configuration release \
  --show-bin-path)"

rm -rf "$APP_ROOT"
mkdir -p "$MACOS_ROOT" "$RESOURCES_ROOT"

cp "$BIN_PATH/NoctwebBrowser" "$MACOS_ROOT/NoctwebBrowser"
cp "$PACKAGE_ROOT/Packaging/Info.plist" "$CONTENTS_ROOT/Info.plist"
chmod 755 "$MACOS_ROOT/NoctwebBrowser"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp=none \
    --entitlements "$PACKAGE_ROOT/Packaging/NoctwebBrowser.entitlements" \
    --sign - \
    "$APP_ROOT"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$PACKAGE_ROOT/Packaging/NoctwebBrowser.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_ROOT"
fi

codesign --verify --strict --verbose=2 "$APP_ROOT"

echo "$APP_ROOT"
