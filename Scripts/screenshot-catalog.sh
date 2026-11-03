#!/usr/bin/env bash
# Usage: screenshot-catalog.sh [output-dir]
# Renders every surface of the app in its main states, light and dark, plus an
# index.html contact sheet. Runs offscreen against throwaway fixtures, so it needs no
# permissions and never touches your real settings, history or recordings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/screenshots}"

mkdir -p "$OUT"
# Only clear what a previous run wrote, in case OUT is a folder with other things in it.
find "$OUT" -maxdepth 1 \( -name '*.png' -o -name 'index.html' \) -delete

echo "▸ Rendering screenshots…"
SCREENSHOTS_DIR="$OUT" swift test --package-path "$ROOT" --filter ScreenshotCatalog

COUNT=$(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
echo "✓ $COUNT screenshots in $OUT"
echo "  Open:  open \"$OUT/index.html\""
