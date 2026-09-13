#!/bin/bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns and site/icon.png.
#
#   Tools/render_icon.sh
#
# The hand-cut texture comes from SVG filters, so headless Chrome rasterizes the
# drawing once at 1024 px and sips scales it down for the smaller sizes. The
# rendered files are committed, so building the app needs no browser.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Google Chrome is needed to render the icon (set CHROME=...)" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp Resources/AppIcon.svg "$WORK/AppIcon.svg"
printf '<html><body style="margin:0;background:transparent"><img src="AppIcon.svg" width="1024" height="1024"></body></html>' > "$WORK/icon.html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --default-background-color=00000000 --virtual-time-budget=2000 --window-size=1024,1024 \
  --screenshot="$WORK/1024.png" "file://$WORK/icon.html" >/dev/null 2>&1
[ -s "$WORK/1024.png" ] || { echo "Chrome did not render the icon" >&2; exit 1; }

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 \
            256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  px=${spec%%:*}
  sips -z "$px" "$px" "$WORK/1024.png" --out "$ICONSET/${spec#*:}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$ICONSET/icon_256x256@2x.png" site/icon.png

# Site favicons from the same drawing: the tile cropped edge to edge without the
# drop shadow, so it reads at tab size, plus a square cream one for Apple touch
# icons (iOS rounds the corners itself).
sed -e 's/viewBox="0 0 1024 1024" width="1024" height="1024"/viewBox="96 96 832 832" width="832" height="832"/' \
    -e 's/ filter="url(#shadow)"//' Resources/AppIcon.svg > site/favicon.svg
cp site/favicon.svg "$WORK/favicon.svg"
printf '<html><body style="margin:0;background:transparent"><img src="favicon.svg" width="1024" height="1024"></body></html>' > "$WORK/fav.html"
printf '<html><body style="margin:0;background:#F1EEE7"><img src="favicon.svg" width="1024" height="1024"></body></html>' > "$WORK/touch.html"
for page in fav touch; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --virtual-time-budget=2000 --window-size=1024,1024 \
    --screenshot="$WORK/$page.png" "file://$WORK/$page.html" >/dev/null 2>&1
done
sips -z 32 32 "$WORK/fav.png" --out site/favicon-32.png >/dev/null
sips -z 16 16 "$WORK/fav.png" --out site/favicon-16.png >/dev/null
sips -z 180 180 "$WORK/touch.png" --out site/apple-touch-icon.png >/dev/null
echo "✓ Resources/AppIcon.icns, site/icon.png and the site favicons"
