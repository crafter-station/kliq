#!/bin/bash
# Builds a Developer ID signed, notarized and stapled Kliq DMG for GitHub Releases.
# The file is always build/Kliq.dmg so releases/latest/download/Kliq.dmg stays valid.
#
#   ./release.sh 0.0.1
#
# One-time setup, stores notarization credentials in the keychain from an App
# Store Connect API key on the signing team (notarytool copies the key in):
#   xcrun notarytool store-credentials kliq-notary \
#     --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <issuer-uuid>
#
#   NOTARY_PROFILE      keychain profile name (default: kliq-notary)
#   CODESIGN_IDENTITY   defaults to the first "Developer ID Application" identity
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>   e.g. ./release.sh 0.0.1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-kliq-notary}"
# Credentials: an App Store Connect API key passed as NOTARY_KEY (path to the .p8),
# NOTARY_KEY_ID and NOTARY_ISSUER, which needs no keychain; otherwise the profile above.
if [ -n "${NOTARY_KEY:-}" ]; then
  NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 -oE '"Developer ID Application: [^"]+"' | tr -d '"' || true)
fi
[ -n "$CODESIGN_IDENTITY" ] || { echo "no Developer ID Application identity in the keychain" >&2; exit 1; }

# What ships must be exactly what is public in the repo, with no uncommitted or
# ignored sound assets.
ls -d Resources/Sounds/*/ >/dev/null 2>&1 || { echo "no bundled sound sets in Resources/Sounds" >&2; exit 1; }
if [ -n "$(git status --porcelain --ignored -- Resources)" ]; then
  echo "Resources/ has uncommitted or ignored files; commit or remove them first:" >&2
  git status --short --ignored -- Resources >&2
  exit 1
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" UNIVERSAL=1 ./build.sh

APP="build/Kliq.app"
DMG="build/Kliq.dmg"
STAGE="build/dmg"

# Notarize the app on its own first and staple its ticket, so it opens even when
# someone launches it for the first time without a network connection.
echo "▸ notarizing the app"
ditto -c -k --keepParent "$APP" build/Kliq-app.zip
xcrun notarytool submit build/Kliq-app.zip "${NOTARY_AUTH[@]}" --wait
xcrun stapler staple "$APP"
rm -f build/Kliq-app.zip

echo "▸ packaging $DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Kliq.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kliq" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"

echo "▸ notarizing the DMG (takes a few minutes)"
xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "✓ $DMG"
echo "  sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
