#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
APP_NAME="Hearsay"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"

# Assemble/sign outside the repo: file providers (iCloud Drive, Dropbox) attach
# xattrs that cannot be stripped, and codesign rejects them
# ("resource fork … detritus not allowed").
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Building release binary…"
swift build -c release --package-path "$ROOT"
BIN_PATH="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$APP_NAME"

echo "▸ Assembling $APP_NAME.app…"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"

"$ROOT/Scripts/sign.sh" "$APP"

mkdir -p "$DIST"
rm -rf "$DIST/$APP_NAME.app"
ditto "$APP" "$DIST/$APP_NAME.app"

echo "▸ Zipping…"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Building DMG…"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$WORK/dmg/$APP_NAME"
rm -f "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov "$DMG" >/dev/null

echo "✓ Done: $ZIP"
echo "✓ Done: $DMG"
