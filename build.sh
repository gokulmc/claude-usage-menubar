#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUNDLE_ID="com.gokul.claude-usage"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"
SIGN_IDENTITY=""  # now handled by notarize-app

echo "==> Building release binary"
swift build -c release

echo "==> Assembling app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Support/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Support/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> Signing + notarizing (Developer ID)"
notarize-app "${APP_BUNDLE}"

echo "==> Installing to ${INSTALL_DIR}"
if [ -d "${INSTALL_DIR}/${APP_BUNDLE}" ]; then
    # Quit any running instance before replacing it.
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "${INSTALL_DIR}/${APP_BUNDLE}"
fi
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/"

echo "==> Launching"
open "${INSTALL_DIR}/${APP_BUNDLE}"

echo "Done. Look for the app in the menu bar."
