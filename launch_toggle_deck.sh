#!/bin/bash
# Builds if the sources are newer than the bundled binary, then launches.
# Does not touch the login item; use install.sh for that.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/ToggleDeck.app"
BUNDLED="$APP/Contents/MacOS/ToggleDeck"

NEEDS_BUILD=0
if [ ! -x "$BUNDLED" ]; then
    NEEDS_BUILD=1
else
    while IFS= read -r src; do
        if [ "$src" -nt "$BUNDLED" ]; then NEEDS_BUILD=1; break; fi
    done < <(find "$SCRIPT_DIR/Sources" -name '*.swift'; echo "$SCRIPT_DIR/Package.swift"; echo "$SCRIPT_DIR/AppIcon.png"; echo "$SCRIPT_DIR/AppIcon.icns"; echo "$SCRIPT_DIR/install.sh")
fi

if [ "$NEEDS_BUILD" -eq 1 ]; then
    echo "Sources changed, rebuilding..."
    bash "$SCRIPT_DIR/install.sh" --no-login-item --no-launch
else
    pkill -x ToggleDeck 2>/dev/null || true
    sleep 0.3
fi

open "$APP"
echo "ToggleDeck running. Click the switch icon in the menu bar."
