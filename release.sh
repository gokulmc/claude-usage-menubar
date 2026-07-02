#!/bin/bash
# Builds ClaudeUsage.app and packages it into a distributable .dmg, for
# people who just want to download and run the app without installing
# Swift or building from source.
#
# Deliberately signs ad-hoc rather than with the local dev identity from
# setup-signing.sh: that identity's trust is only meaningful on this machine,
# so shipping a binary "signed" by it would be misleading. A downloaded,
# never-rebuilt binary only needs a *stable* identity (so a single "Always
# Allow" click sticks), and ad-hoc signing already gives that -- there's no
# untrusted certificate chain involved, so none of the re-validation/re-prompt
# behavior documented in the README's Troubleshooting section applies here.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
VERSION="$(defaults read "$(pwd)/Support/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")"
DMG_NAME="ClaudeUsage-${VERSION}.dmg"
STAGING_DIR=".dmg-staging"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling app bundle"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Support/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Code signing (ad-hoc, for a stable standalone identity)"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Building ${DMG_NAME}"
rm -rf "${STAGING_DIR}" "${DMG_NAME}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_NAME}"
rm -rf "${STAGING_DIR}"

echo "Done: ${DMG_NAME}"
echo "Note: this build isn't notarized. On first launch, right-click the app"
echo "in /Applications and choose Open, since Gatekeeper will otherwise warn"
echo "about an unidentified developer."
