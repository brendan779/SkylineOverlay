#!/bin/bash
#
# Builds Skyline (Release) and packages it into a distributable .dmg.
# Output: dist/Skyline.dmg — upload it to a GitHub release.
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Skyline"
VERSION="0.1.0"
DERIVED="$PWD/.dmgbuild"
STAGING="$PWD/.dmgstaging"
LOG="$PWD/.dmgbuild.log"
DMG_OUT="$PWD/dist/${APP_NAME}.dmg"

cleanup() { rm -rf "$DERIVED" "$STAGING" "$LOG"; }
trap cleanup EXIT

echo "[1/4] Building ${APP_NAME} ${VERSION} (Release)…"
if ! xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
        -configuration Release -derivedDataPath "$DERIVED" \
        clean build > "$LOG" 2>&1; then
    echo "Build failed:"
    tail -25 "$LOG"
    exit 1
fi

APP_PATH="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Build succeeded but ${APP_NAME}.app was not found at $APP_PATH"
    exit 1
fi

echo "[2/4] Staging disk image contents…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "[3/4] Creating compressed disk image…"
mkdir -p "$(dirname "$DMG_OUT")"
rm -f "$DMG_OUT"
hdiutil create -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGING" -ov -format UDZO "$DMG_OUT" > /dev/null

echo "[4/4] Done."
echo "  → $DMG_OUT  ($(du -h "$DMG_OUT" | cut -f1))"
