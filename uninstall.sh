#!/bin/bash
# Remove hdr-always-on, including the older shell-script version.
set -uo pipefail

DOMAIN="gui/$(id -u)"

echo "Uninstalling hdr-always-on..."

for label in com.autonomath.hdr-always-on com.user.enable-hdr; do
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -f "$HOME/.local/bin/hdr-always-on" "$HOME/.local/bin/enable-hdr.sh"
rm -f "$HOME/Library/Logs/hdr-always-on.log" /tmp/enable-hdr.log
rm -rf "$HOME/.config/hdr-always-on"

# Also remove the receipt left by the .pkg installer.
if pkgutil --pkg-info com.autonomath.hdr-always-on &>/dev/null; then
    echo "Removing pkg receipt..."
    sudo pkgutil --forget com.autonomath.hdr-always-on 2>/dev/null || true
fi

echo "Done. HDR will no longer be switched on automatically."
