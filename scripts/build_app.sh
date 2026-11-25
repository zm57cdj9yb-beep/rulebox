#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/RuleBox.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"

# Generate AppIcon.icns from Resources/AppIcon.svg using qlmanage/sips + iconutil
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

qlmanage -t -s 1024 -o "$BUILD_DIR" "$ROOT_DIR/Resources/AppIcon.svg" >/dev/null 2>&1 || true
BASE_PNG="$BUILD_DIR/AppIcon.svg.png"
if [ -f "$BASE_PNG" ]; then
  for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz" "$BASE_PNG" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    sz2=$((sz * 2))
    sips -z "$sz2" "$sz2" "$BASE_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"
  rm -f "$BASE_PNG"
fi
rm -rf "$ICONSET"

swift build -c "$CONFIG" --product RuleBox

BIN_PATH="$ROOT_DIR/.build/$CONFIG/RuleBox"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/RuleBox"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi

codesign --force --sign - "$MACOS_DIR/RuleBox"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

echo "Built and signed: $APP_BUNDLE"
