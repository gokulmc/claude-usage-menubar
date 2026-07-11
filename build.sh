#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUNDLE_ID="com.gokul.claude-usage"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"
SIGN_IDENTITY="ClaudeUsageLocalSign"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Support/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Support/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

if security find-certificate -c "${SIGN_IDENTITY}" >/dev/null 2>&1; then
    echo "==> Code signing (${SIGN_IDENTITY})"
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> Code signing (ad-hoc — ${SIGN_IDENTITY} not found in keychain)"
    echo "    Tip: run ./setup-signing.sh once to stop macOS from repeatedly"
    echo "    asking for your password to read the Keychain item."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

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
