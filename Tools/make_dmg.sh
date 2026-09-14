#!/bin/bash
# Packages an app into the styled installer DMG: the app and an Applications
# shortcut over Resources/DMGBackground.tiff. release.sh signs and notarizes it.
#
#   Tools/make_dmg.sh [build/Kliq.app] [build/Kliq.dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/Kliq.app}"
DMG="${2:-build/Kliq.dmg}"
[ -d "$APP" ] || { echo "$APP not found, run make build first" >&2; exit 1; }
command -v uvx >/dev/null || { echo "uv is needed to run dmgbuild (brew install uv)" >&2; exit 1; }

rm -f "$DMG"
uvx --from dmgbuild==1.6.7 dmgbuild -s Tools/dmg_settings.py -D app="$APP" "Kliq Installer" "$DMG"
echo "✓ $DMG"
