#!/bin/sh
# Builds SpeedReader.app — a proper bundle so macOS attributes the
# Screen Recording permission to Speed Reader itself (a bare terminal
# binary gets attributed to the parent terminal app instead).
#
# Usage: Support/build-app.sh [--run]
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP="build/SpeedReader.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SpeedReader "$APP/Contents/MacOS/SpeedReader"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then
    cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Prefer a stable signing identity (e.g. a self-signed "SpeedReader Dev"
# certificate, or a real Apple Development cert) so the Screen Recording
# grant survives rebuilds. Ad-hoc fallback changes the code hash on every
# build, which silently invalidates the TCC grant.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
if [ -n "$IDENTITY" ]; then
    echo "Signing with: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "No signing identity found - using ad-hoc signature."
    echo "(Screen Recording permission will reset on each rebuild;"
    echo " create a self-signed 'SpeedReader Dev' code-signing cert"
    echo " in Keychain Access to fix this.)"
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
if [ "$1" = "--run" ]; then
    pkill -x SpeedReader 2>/dev/null || true
    open "$APP"
    echo "Launched."
fi
