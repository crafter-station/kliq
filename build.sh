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
# Prefer a real Apple Development identity when one is in the keychain: macOS
# ties the Accessibility grant to the signature, and ad-hoc signatures change
# on every build. Override with CODESIGN_IDENTITY, or set it to "-" for ad-hoc.
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 -oE '"Apple Development: [^"]+"' | tr -d '"' || true)
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

MARK=Sources/Kliq/UI/Components/KliqLogo.swift
ICNS="$BUILD_DIR/AppIcon.icns"
if [ ! -f "$ICNS" ] || [ "$MARK" -nt "$ICNS" ] || [ Tools/make_icon.swift -nt "$ICNS" ]; then
  echo "▸ rendering app icon"
  rm -rf "$BUILD_DIR/AppIcon.iconset"
  if swiftc -parse-as-library -O -o "$BUILD_DIR/make_icon" Tools/make_icon.swift "$MARK" 2>/dev/null \
     && "$BUILD_DIR/make_icon" "$BUILD_DIR/AppIcon.iconset" >/dev/null \
     && iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$ICNS" 2>/dev/null; then
    :
  else
    echo "  (icon rendering skipped)"
  fi
fi
[ -f "$BUILD_DIR/AppIcon.icns" ] && cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Hardened runtime on every build so local builds behave like notarized ones.
# A secure timestamp is only needed (and only fetched) for Developer ID builds.
TIMESTAMP="--timestamp=none"
case "$IDENTITY" in "Developer ID"*) TIMESTAMP="--timestamp" ;; esac
echo "▸ codesign ($IDENTITY)"
codesign --force --options runtime --entitlements Resources/Kliq.entitlements \
  "$TIMESTAMP" --sign "$IDENTITY" "$APP"

echo "✓ built $APP"
echo "  open \"$APP\""
