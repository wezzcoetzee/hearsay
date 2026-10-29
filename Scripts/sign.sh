#!/usr/bin/env bash
# Usage: sign.sh <path/to/App.app>
# Signs with the stable local identity (see setup-signing.sh) so TCC grants
# survive rebuilds. Falls back to ad-hoc, which re-prompts after every build.
set -euo pipefail

APP="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${SIGN_IDENTITY:-WhatDidISay Local Signing}"

if ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "⚠ No \"$IDENTITY\" identity; signing ad-hoc. Permissions will re-prompt after each rebuild."
    echo "  Fix once with: ./Scripts/setup-signing.sh"
    IDENTITY="-"
fi

echo "▸ Signing with ${IDENTITY/#-/ad-hoc}…"
codesign --force --sign "$IDENTITY" \
    --options runtime \
    --entitlements "$ROOT/Resources/WhatDidISay.entitlements" \
    "$APP"
codesign --verify --strict "$APP"
