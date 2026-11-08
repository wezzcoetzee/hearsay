#!/usr/bin/env bash
# Usage: appstore-screenshots.sh [output-dir]
# Renders the Mac App Store screenshots (2880 x 1800, a headline beside the real app)
# into docs/appstore/, where README.md shows them. Like screenshots.sh it runs
# offscreen against throwaway fixtures: no permissions, none of your real data.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/appstore}"

mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -name '*.png' -delete

echo "▸ Rendering App Store screenshots…"
APPSTORE_SCREENSHOTS_DIR="$OUT" swift test --package-path "$ROOT" --filter AppStoreScreenshots

COUNT=$(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
echo "✓ $COUNT App Store screenshots in $OUT"
