#!/bin/bash
# Renders Tools/dmg.html into Resources/DMGBackground.tiff, the Kliq.dmg window
# background, with 1x and 2x images in one file so it stays sharp on Retina screens.
#
#   Tools/render_dmg_background.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Google Chrome is needed to render the image (set CHROME=...)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for SCALE in 1 2; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$SCALE \
    --virtual-time-budget=6000 --window-size=660,420 \
    --screenshot="$TMP/bg-$SCALE.png" "file://$PWD/Tools/dmg.html" >/dev/null 2>&1
  [ -s "$TMP/bg-$SCALE.png" ] || { echo "Chrome did not render the image" >&2; exit 1; }
done
# Tag the 2x image as 144 dpi so Finder draws it at the same size in points.
sips -s dpiWidth 144 -s dpiHeight 144 "$TMP/bg-2.png" >/dev/null
tiffutil -cathidpicheck "$TMP/bg-1.png" "$TMP/bg-2.png" -out Resources/DMGBackground.tiff 2>/dev/null
echo "✓ Resources/DMGBackground.tiff"
