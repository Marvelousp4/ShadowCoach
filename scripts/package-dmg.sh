#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Shadow Coach"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
SIGN_IDENTITY="${SHADOW_COACH_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${SHADOW_COACH_NOTARY_PROFILE:-}"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --volumeName "$APP_NAME" \
    --format UDZO \
    "$STAGING_DIR" \
    "$DMG_PATH"
else
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
fi

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

rm -rf "$STAGING_DIR"
echo "$DMG_PATH"
