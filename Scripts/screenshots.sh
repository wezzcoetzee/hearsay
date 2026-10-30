#!/bin/bash
# Renders the App Store / README screenshots from screenshots/manifest.json.
# Needs a full Xcode (for SwiftUI macros) and the app-store-screenshots composite.sh:
#   COMPOSITE=/path/to/composite.sh ./Scripts/screenshots.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/screenshots/manifest.json"
RAW="$ROOT/screenshots/raw/mac"
FRAMED="$ROOT/screenshots/framed/mac"
: "${COMPOSITE:?set COMPOSITE to the path of composite.sh}"

swift build --package-path "$ROOT"
"$(swift build --package-path "$ROOT" --show-bin-path)/WhatDidISay" -renderScreenshots "$RAW"

mkdir -p "$FRAMED"
m() { jq -r "$1" "$MANIFEST"; }
while IFS= read -r screen; do
  id=$(jq -r .id <<<"$screen")
  "$COMPOSITE" --shot "$RAW/$id.png" --frame "$(m .frame)" --size "$(m .compositeSize)" \
    --headline "$(jq -r .headline <<<"$screen")" --subheadline "$(jq -r .subheadline <<<"$screen")" \
    --template "$ROOT/screenshots/frame.html" --bg1 "$(m .bg1)" --bg2 "$(m .bg2)" --text "$(m .text)" --out "$FRAMED/$id.png"
done < <(jq -c '.screens[]' "$MANIFEST")
