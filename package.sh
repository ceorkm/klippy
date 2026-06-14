#!/bin/bash
# Klippy — build, sign (Developer ID), package DMG, and notarize.
# Requires: Xcode, a "Developer ID Application" cert, and a notarytool
# keychain profile (xcrun notarytool store-credentials <profile> ...).
# Configure identity in .release.env (copy from .release.env.example).
set -euo pipefail

# Load signing identity from a local, gitignored config (see .release.env.example).
# Values can also be supplied via the environment instead of the file.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HERE}/.release.env" ]]; then
  # shellcheck disable=SC1091
  source "${HERE}/.release.env"
fi

: "${TEAM_ID:?Set TEAM_ID (Apple Developer Team ID) in .release.env or the environment}"
: "${SIGN_ID:?Set SIGN_ID (e.g. 'Developer ID Application: NAME (TEAMID)') in .release.env or the environment}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE (notarytool keychain profile name) in .release.env or the environment}"

PROJECT="Klippy.xcodeproj"
SCHEME="Klippy"
CONFIG="Release"
BUNDLE_ID="com.klippy.Klippy"

DERIVED=".dmg-build"
APP_OUT="${DERIVED}/Build/Products/${CONFIG}/Klippy.app"
STAGING="dist/dmg-staging"
DMG_OUT="dist/Klippy.dmg"
DMG_BG="dist/dmg-background.png"

echo "==> [1/6] Building & signing (${CONFIG}) with: ${SIGN_ID}"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGN_ID}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build | tail -8

echo "==> [2/6] Verifying app signature"
codesign --verify --strict --verbose=2 "${APP_OUT}"
codesign -dvv "${APP_OUT}" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime" | head

echo "==> [3/6] Staging app for DMG"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R "${APP_OUT}" "${STAGING}/Klippy.app"

echo "==> [4/6] Building DMG -> ${DMG_OUT}"
rm -f "${DMG_OUT}" dist/rw.*.dmg
create-dmg \
  --volname "Klippy" \
  --background "${DMG_BG}" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 110 \
  --icon "Klippy.app" 170 190 \
  --app-drop-link 490 190 \
  --hdiutil-quiet \
  "${DMG_OUT}" \
  "${STAGING}/Klippy.app"

echo "==> [5/6] Notarizing ${DMG_OUT} (profile: ${NOTARY_PROFILE})"
xcrun notarytool submit "${DMG_OUT}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

echo "==> [6/6] Stapling"
xcrun stapler staple "${DMG_OUT}"
xcrun stapler validate "${DMG_OUT}"
spctl -a -t open --context context:primary-signature -vv "${DMG_OUT}" || true

echo "✅ Done: ${DMG_OUT}"
