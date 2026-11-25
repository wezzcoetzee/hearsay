#!/bin/bash
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Hearsay"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/$APP_NAME"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

"$ROOT/Scripts/sign.sh" "$APP_DIR"

echo "✓ Built $APP_DIR"
echo "  Run:  open \"$APP_DIR\""
