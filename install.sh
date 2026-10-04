#!/bin/bash
set -e

REPO="autonomath/hdr-always-on"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"

INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.enable-hdr"

echo "Installing hdr-always-on..."

# Detect if running from a local clone or via curl
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [ -f "$SCRIPT_DIR/enable-hdr.sh" ] && [ -f "$SCRIPT_DIR/com.user.enable-hdr.plist" ]; then
    echo "Installing from local files..."
    ENABLE_HDR="$(cat "$SCRIPT_DIR/enable-hdr.sh")"
    PLIST_TEMPLATE="$(cat "$SCRIPT_DIR/com.user.enable-hdr.plist")"
else
    echo "Downloading from GitHub..."
    ENABLE_HDR="$(curl -fsSL "$BASE_URL/enable-hdr.sh")"
    PLIST_TEMPLATE="$(curl -fsSL "$BASE_URL/com.user.enable-hdr.plist")"
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Install script
echo "$ENABLE_HDR" > "$INSTALL_DIR/enable-hdr.sh"
chmod +x "$INSTALL_DIR/enable-hdr.sh"

# Install LaunchAgent with correct path
echo "$PLIST_TEMPLATE" | sed "s|__SCRIPT_PATH__|$INSTALL_DIR/enable-hdr.sh|g" \
    > "$PLIST_DIR/$PLIST_NAME.plist"

# Unload if already running
launchctl unload "$PLIST_DIR/$PLIST_NAME.plist" 2>/dev/null || true

# Load
launchctl load "$PLIST_DIR/$PLIST_NAME.plist"

echo ""
echo "Done! HDR will be enabled on all external displays at login and every 15 minutes."
echo "Logs: /tmp/enable-hdr.log"
echo ""
echo "To uninstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/$BRANCH/uninstall.sh | bash"
