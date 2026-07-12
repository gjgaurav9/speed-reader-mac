#!/bin/sh
# Builds a distributable DMG at build/SpeedReader.dmg.
#
# NOTE on sharing with others: without Apple Developer ID signing +
# notarization, recipients must right-click → Open the app the first time
# (Gatekeeper), and macOS will show its capture-consent prompts. To ship
# cleanly you need a $99/yr Apple Developer account, then:
#   codesign --force --deep --options runtime \
#     --sign "Developer ID Application: YOUR NAME (TEAMID)" build/SpeedReader.app
#   xcrun notarytool submit build/SpeedReader.dmg \
#     --keychain-profile speedreader --wait
#   xcrun stapler staple build/SpeedReader.dmg
set -e
cd "$(dirname "$0")/.."

Support/build-app.sh

STAGING="build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R build/SpeedReader.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f build/SpeedReader.dmg
hdiutil create -volname "Speed Reader" -srcfolder "$STAGING" -ov -format UDZO build/SpeedReader.dmg
rm -rf "$STAGING"
echo "Created build/SpeedReader.dmg"
