#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ROOT="$PACKAGE_ROOT/dist/Noctweb Lab.app"
CONTENTS_ROOT="$APP_ROOT/Contents"
MACOS_ROOT="$CONTENTS_ROOT/MacOS"
RESOURCES_ROOT="$CONTENTS_ROOT/Resources"
SIGNING_IDENTITY="${NOCTWEB_CODESIGN_IDENTITY:--}"

swift build \
  --package-path "$PACKAGE_ROOT" \
  --configuration release \
  --product NoctwebLab

BIN_PATH="$(swift build \
  --package-path "$PACKAGE_ROOT" \
  --configuration release \
  --show-bin-path)"

rm -rf "$APP_ROOT"
mkdir -p "$MACOS_ROOT" "$RESOURCES_ROOT"

cp "$BIN_PATH/NoctwebLab" "$MACOS_ROOT/NoctwebLab"
cp "$PACKAGE_ROOT/Packaging/Info.plist" "$CONTENTS_ROOT/Info.plist"
chmod 755 "$MACOS_ROOT/NoctwebLab"

codesign \
  --force \
  --deep \
  --sign "$SIGNING_IDENTITY" \
  "$APP_ROOT"

codesign --verify --deep --strict --verbose=2 "$APP_ROOT"

echo "$APP_ROOT"
