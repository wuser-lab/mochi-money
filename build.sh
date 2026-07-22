#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Mochi Money.app"
DMG_STAGE="$BUILD_DIR/dmg"
OUTPUT_DIR="${1:-$ROOT_DIR/../../outputs}"
PYTHON_BIN="${MOCHI_PYTHON:-/Users/eldar/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3}"
if [[ ! -x "$PYTHON_BIN" ]]; then PYTHON_BIN="python3"; fi

rm -rf "$APP_DIR" "$DMG_STAGE" "$BUILD_DIR/AppIcon.iconset" "$BUILD_DIR/AppIcon.icns"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DMG_STAGE" "$OUTPUT_DIR"

swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework Charts \
  "$ROOT_DIR"/Sources/*.swift -o "$BUILD_DIR/MochiMoney-arm64"
swiftc -swift-version 5 -parse-as-library -O -target x86_64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework Charts \
  "$ROOT_DIR"/Sources/*.swift -o "$BUILD_DIR/MochiMoney-x86_64"
lipo -create "$BUILD_DIR/MochiMoney-arm64" "$BUILD_DIR/MochiMoney-x86_64" -output "$APP_DIR/Contents/MacOS/MochiMoney"

"$PYTHON_BIN" "$ROOT_DIR/make_icon.py"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"

cp -R "$APP_DIR" "$DMG_STAGE/Mochi Money.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$ROOT_DIR/README.md" "$DMG_STAGE/Read Me.txt"
rm -f "$OUTPUT_DIR/Mochi-Money.dmg"
hdiutil create -volname "Mochi Money" -srcfolder "$DMG_STAGE" -ov -format UDZO "$OUTPUT_DIR/Mochi-Money.dmg"
