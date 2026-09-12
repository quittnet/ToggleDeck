#!/bin/bash
# Builds ToggleDeck, wraps it in an app bundle, and (unless --no-login-item)
# registers it to start at login.
#
# The app must run from a bundle, not as a loose binary: CoreBluetooth aborts
# the process on sight if the running bundle has no NSBluetoothAlwaysUsageDescription,
# and TCC has nothing to pin Full Disk Access to without a bundle identifier.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/.build/release/ToggleDeck"
APP="$HOME/Applications/ToggleDeck.app"
PLIST="$HOME/Library/LaunchAgents/com.user.toggledeck.plist"

WITH_LOGIN_ITEM=1
LAUNCH=1
REGEN_ICON=0
for arg in "$@"; do
    case "$arg" in
        --no-login-item) WITH_LOGIN_ITEM=0 ;;
        --no-launch)     LAUNCH=0 ;;
        --regen-icon)    REGEN_ICON=1 ;;
    esac
done

echo "Building..."
cd "$SCRIPT_DIR"
swift build -c release -Xswiftc -warnings-as-errors

# Package the source artwork when it changes, or when regeneration is requested.
if [ ! -f "$SCRIPT_DIR/AppIcon.icns" ] || [ "$REGEN_ICON" -eq 1 ] || [ "$SCRIPT_DIR/AppIcon.png" -nt "$SCRIPT_DIR/AppIcon.icns" ]; then
    echo "Generating app icon..."
    "$BINARY" --make-icon "$SCRIPT_DIR/AppIcon.icns"
fi

echo "Creating app bundle..."
mkdir -p "$HOME/Applications"
INSTALL_STAGE="$(mktemp -d "$HOME/Applications/.ToggleDeck-install.XXXXXX")"
trap 'rm -rf "$INSTALL_STAGE"' EXIT
STAGED_APP="$INSTALL_STAGE/ToggleDeck.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BINARY" "$STAGED_APP/Contents/MacOS/ToggleDeck"
cp "$SCRIPT_DIR/AppIcon.icns" "$STAGED_APP/Contents/Resources/ToggleDeckIcon-v21.icns"
if [ -f "$SCRIPT_DIR/AppIcon.png" ]; then
    cp "$SCRIPT_DIR/AppIcon.png" "$STAGED_APP/Contents/Resources/AppIconSource.png"
fi

cat > "$STAGED_APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ToggleDeck</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.toggledeck</string>
    <key>CFBundleName</key>
    <string>ToggleDeck</string>
    <key>CFBundleDisplayName</key>
    <string>ToggleDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.2</string>
    <key>CFBundleVersion</key>
    <string>4</string>
    <key>CFBundleIconFile</key>
    <string>ToggleDeckIcon-v21</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>ToggleDeck reads and changes the Bluetooth power state for the Bluetooth switch.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ToggleDeck uses System Events to change the appearance and mute state.</string>
</dict>
</plist>
EOF

# Keep the bundle identifier and existing icon. macOS may ask to confirm
# permissions again when an ad-hoc signed executable changes.
echo "Signing (ad-hoc)..."
codesign --sign - --force "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
plutil -lint "$STAGED_APP/Contents/Info.plist"

# Finish building and signing before replacing the working installation.
BACKUP_DIR="$SCRIPT_DIR/.backups/install-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
pkill -x ToggleDeck 2>/dev/null || true
sleep 0.4
if [ -d "$APP" ]; then mv "$APP" "$BACKUP_DIR/ToggleDeck.app"; fi
if ! mv "$STAGED_APP" "$APP"; then
    if [ -d "$BACKUP_DIR/ToggleDeck.app" ]; then mv "$BACKUP_DIR/ToggleDeck.app" "$APP"; fi
    exit 1
fi

if [ "$WITH_LOGIN_ITEM" -eq 1 ]; then
    echo "Registering login item..."
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.toggledeck</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/ToggleDeck</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/com.user.toggledeck" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
fi

if [ "$LAUNCH" -eq 1 ]; then
    open "$APP"
    echo ""
    echo "ToggleDeck is running. Look for the switch icon in your menu bar."
fi

cat << EOF

Installed to: $APP

20 everyday settings. Use Customize to choose your menu controls.
macOS may request Automation or Bluetooth permission when a control needs it.
EOF
