#!/bin/bash
# Builds Kliq.app into ./build using Swift Package Manager (no Xcode project needed).
#
#   ./build.sh                  release build
#   CONFIG=debug ./build.sh     debug build
#   CODESIGN_IDENTITY="Apple Development: You (TEAMID)" ./build.sh
#   VERSION=1.2.0 BUILD_NUMBER=42 ./build.sh    stamp the bundle version
#
# For a notarized DMG to distribute, use ./release.sh, which calls this script.
#
# Note on Accessibility permission: macOS ties the grant to the code signature.
# With ad-hoc signing every rebuild produces a new signature, so you will be asked
# to re-grant permission after each build. Signing with a real identity avoids that.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Kliq"
CONFIG="${CONFIG:-release}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

# Keep the product library exact. This guards both local builds and releases from
# silently shipping an extra profile or omitting one of the definitive seven.
EXPECTED_SOUND_SETS=("Cherry" "DSA" "KAT" "MT3" "OEM" "SA" "XDA")
EXPECTED_SOUND_COUNTS=(128 128 128 109 128 124 128)
ACTUAL_SOUND_SETS=$(find Resources/Sounds -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort)
EXPECTED_SOUND_SET_LIST=$(printf '%s\n' "${EXPECTED_SOUND_SETS[@]}" | LC_ALL=C sort)
if [ "$ACTUAL_SOUND_SETS" != "$EXPECTED_SOUND_SET_LIST" ]; then
  echo "sound library must contain exactly: ${EXPECTED_SOUND_SETS[*]}" >&2
  echo "found: ${ACTUAL_SOUND_SETS//$'\n'/, }" >&2
  exit 1
fi
shopt -s nullglob
for SET_INDEX in "${!EXPECTED_SOUND_SETS[@]}"; do
  SET_NAME="${EXPECTED_SOUND_SETS[$SET_INDEX]}"
  DOWN_SAMPLES=("Resources/Sounds/$SET_NAME"/*-down.wav)
  UP_SAMPLES=("Resources/Sounds/$SET_NAME"/*-up.wav)
  if [ "${#DOWN_SAMPLES[@]}" -eq 0 ] || [ "${#UP_SAMPLES[@]}" -eq 0 ]; then
    echo "sound set $SET_NAME needs both press and release samples" >&2
    exit 1
  fi
  SAMPLE_COUNT=$(find "Resources/Sounds/$SET_NAME" -maxdepth 1 -type f -name '*.wav' | wc -l | tr -d ' ')
  if [ "$SAMPLE_COUNT" -ne "${EXPECTED_SOUND_COUNTS[$SET_INDEX]}" ]; then
    echo "sound set $SET_NAME must contain ${EXPECTED_SOUND_COUNTS[$SET_INDEX]} WAV files; found $SAMPLE_COUNT" >&2
    exit 1
  fi
done
shopt -u nullglob

EXPECTED_EFFECT_FILES=$(printf '%s\n' click.wav ding-down.wav ding-up.wav ding.wav left-down.wav left-up.wav right-down.wav right-up.wav | LC_ALL=C sort)
ACTUAL_EFFECT_FILES=$(find Resources/Sounds -maxdepth 1 -type f -name '*.wav' -exec basename {} \; | LC_ALL=C sort)
if [ "$ACTUAL_EFFECT_FILES" != "$EXPECTED_EFFECT_FILES" ]; then
  echo "the bundled effects do not match the definitive sound library" >&2
  exit 1
fi
# macOS ties the Accessibility grant to the signature, so sign local builds with the
# same Developer ID that releases use when it's in the keychain; switching between
# identities makes an existing grant stop applying. Falls back to an Apple
# Development identity. Override with CODESIGN_IDENTITY, or set it to "-" for ad-hoc.
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
  CODESIGN_IDENTITY=$(echo "$IDENTITIES" | grep -m1 -oE '"Developer ID Application: [^"]+"' | tr -d '"' || true)
  [ -n "$CODESIGN_IDENTITY" ] || CODESIGN_IDENTITY=$(echo "$IDENTITIES" | grep -m1 -oE '"Apple Development: [^"]+"' | tr -d '"' || true)
fi
IDENTITY="${CODESIGN_IDENTITY:--}"

# UNIVERSAL=1 builds one binary for Apple silicon and Intel (release.sh sets it).
ARCH_FLAGS=""
[ "${UNIVERSAL:-0}" = "1" ] && ARCH_FLAGS="--arch arm64 --arch x86_64"
echo "▸ swift build ($CONFIG${ARCH_FLAGS:+, universal})"
swift build -c "$CONFIG" --product "$APP_NAME" $ARCH_FLAGS
BIN="$(swift build -c "$CONFIG" --product "$APP_NAME" $ARCH_FLAGS --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "build failed: $BIN missing" >&2; exit 1; }

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
[ -n "${VERSION:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[ -n "${BUILD_NUMBER:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# The icon is drawn in Resources/AppIcon.svg and rendered by Tools/render_icon.sh;
# the rendered .icns is committed, so building needs no browser.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Hardened runtime on every build so local builds behave like notarized ones.
# A secure timestamp is only needed (and only fetched) for Developer ID builds.
TIMESTAMP="--timestamp=none"
case "$IDENTITY" in "Developer ID"*) TIMESTAMP="--timestamp" ;; esac
echo "▸ codesign ($IDENTITY)"
codesign --force --options runtime --entitlements Resources/Kliq.entitlements \
  "$TIMESTAMP" --sign "$IDENTITY" "$APP"

echo "✓ built $APP"
echo "  open \"$APP\""
