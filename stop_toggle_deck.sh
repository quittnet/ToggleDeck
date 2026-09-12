#!/bin/bash
# Stops ToggleDeck. Pass --disable-login-item to also stop it starting at login.
set -e

for arg in "$@"; do
    if [ "$arg" = "--disable-login-item" ]; then
        launchctl bootout "gui/$(id -u)/com.user.toggledeck" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/com.user.toggledeck.plist"
        echo "Login item removed."
    fi
done

if pkill -x ToggleDeck 2>/dev/null; then
    echo "ToggleDeck stopped."
else
    echo "ToggleDeck was not running."
fi
