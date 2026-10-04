#!/bin/bash
set -e

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.enable-hdr"

echo "Uninstalling hdr-always-on..."

launchctl unload "$PLIST_DIR/$PLIST_NAME.plist" 2>/dev/null || true
rm -f "$PLIST_DIR/$PLIST_NAME.plist"
rm -f "$HOME/.local/bin/enable-hdr.sh"
rm -f /tmp/enable-hdr.log

# Also remove if installed via .pkg
if pkgutil --pkg-info com.autonomath.hdr-always-on &>/dev/null; then
    echo "Removing pkg receipt..."
    sudo pkgutil --forget com.autonomath.hdr-always-on 2>/dev/null || true
fi

echo "Done. HDR will no longer be automatically enabled."
