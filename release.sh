#!/bin/bash
# Builds ClaudeUsage.app and packages it into a distributable .dmg, for
# people who just want to download and run the app without installing
# Swift or building from source.
#
# Signs with the Developer ID identity and notarizes the app before packaging
# into the DMG, so the downloaded app launches without Gatekeeper warnings and
# "Always Allow" on the Keychain prompt genuinely sticks.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUILD_DIR=".build/release"
# Deliberately NOT "ClaudeUsage.app" -- that path is build.sh's, which installs
# a *trusted-identity* build to /Applications for daily use. Reusing the same
# name here risked this ad-hoc-signed copy getting mistaken for (or manually
# copied over) that one, silently downgrading the installed app's signature
# and bringing back the repeated Keychain prompts.
STAGING_DIR=".release-build"
APP_BUNDLE="${STAGING_DIR}/${APP_NAME}.app"
VERSION="$(defaults read "$(pwd)/Support/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")"
DMG_NAME="ClaudeUsage-${VERSION}.dmg"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling app bundle"
rm -rf "${STAGING_DIR}" "${DMG_NAME}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Support/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Support/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> Signing + notarizing (Developer ID)"
notarize-app "${APP_BUNDLE}"

echo "==> Building ${DMG_NAME}"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_NAME}"
rm -rf "${STAGING_DIR}"

echo "Done: ${DMG_NAME}"
