#!/bin/bash
# Install or update hdr-always-on for the current user.
set -euo pipefail

REPO="autonomath/hdr-always-on"
BRANCH="${HDR_ALWAYS_ON_BRANCH:-main}"
BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"

LABEL="com.autonomath.hdr-always-on"
OLD_LABEL="com.user.enable-hdr"
DOMAIN="gui/$(id -u)"
BIN_DIR="$HOME/.local/bin"
BINARY="$BIN_DIR/hdr-always-on"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/hdr-always-on.log"

echo "Installing hdr-always-on..."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Use the files next to this script when it runs from a clone, otherwise download them.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bin/hdr-always-on" ] && [ -f "$SCRIPT_DIR/$LABEL.plist" ]; then
    echo "Using files from $SCRIPT_DIR"
    cp "$SCRIPT_DIR/bin/hdr-always-on" "$WORK_DIR/hdr-always-on"
    cp "$SCRIPT_DIR/$LABEL.plist" "$WORK_DIR/agent.plist"
else
    echo "Downloading from GitHub..."
    curl -fsSL "$BASE_URL/bin/hdr-always-on" -o "$WORK_DIR/hdr-always-on"
    curl -fsSL "$BASE_URL/$LABEL.plist" -o "$WORK_DIR/agent.plist"
fi
chmod 755 "$WORK_DIR/hdr-always-on"
"$WORK_DIR/hdr-always-on" --version >/dev/null

# Stop the running agent and remove the older shell-script version.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$OLD_LABEL" 2>/dev/null || true
rm -f "$PLIST_DIR/$OLD_LABEL.plist" "$BIN_DIR/enable-hdr.sh"

mkdir -p "$BIN_DIR" "$PLIST_DIR" "$(dirname "$LOG_FILE")"
install -m 755 "$WORK_DIR/hdr-always-on" "$BINARY"
sed -e "s|__BINARY_PATH__|$BINARY|g" -e "s|__LOG_PATH__|$LOG_FILE|g" "$WORK_DIR/agent.plist" > "$PLIST"
plutil -lint -s "$PLIST"

# Clear any earlier `launchctl disable`, which would otherwise keep the agent from loading.
launchctl enable "$DOMAIN/$LABEL"
loaded=0
for _ in 1 2 3 4 5; do
    if launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then
        loaded=1
        break
    fi
    sleep 1
done
if [ "$loaded" -ne 1 ]; then
    launchctl bootstrap "$DOMAIN" "$PLIST"
fi

echo ""
echo "Done. hdr-always-on checks your external displays after wake, unlock, and display changes, and every 15 minutes."
echo ""
"$BINARY" list || true
echo ""
echo "Leave a display alone:  $BINARY exclude \"DISPLAY NAME\""
echo "Log:                    $LOG_FILE"
echo "Uninstall:              curl -fsSL $BASE_URL/uninstall.sh | bash"
