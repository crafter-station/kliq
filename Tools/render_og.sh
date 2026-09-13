#!/bin/bash
# Renders Tools/og.html into site/og.png, the 1200×630 link preview image.
#
#   Tools/render_og.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Google Chrome is needed to render the image (set CHROME=...)" >&2; exit 1; }

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --virtual-time-budget=6000 --window-size=1200,630 \
  --screenshot="$PWD/site/og.png" "file://$PWD/Tools/og.html" >/dev/null 2>&1
[ -s site/og.png ] || { echo "Chrome did not render the image" >&2; exit 1; }
echo "✓ site/og.png"
