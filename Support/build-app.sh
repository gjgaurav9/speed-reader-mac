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
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SpeedReader "$APP/Contents/MacOS/SpeedReader"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature for local dev. Note: every rebuild changes the code
# hash, so macOS may ask you to re-enable Screen Recording after a
# rebuild. A stable Apple Development certificate fixes that (Milestone 5).
codesign --force --deep --sign - "$APP"

echo "Built $APP"
if [ "$1" = "--run" ]; then
    pkill -x SpeedReader 2>/dev/null || true
    open "$APP"
    echo "Launched."
fi
