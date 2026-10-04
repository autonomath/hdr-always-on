#!/bin/bash
set -e

# Build a signed and optionally notarized .pkg installer for hdr-always-on
#
# Usage:
#   ./pkg/build-pkg.sh                    # Build and sign only
#   ./pkg/build-pkg.sh --notarize PROFILE # Build, sign, and notarize
#
# Before notarizing, store credentials once:
#   xcrun notarytool store-credentials "hdr-always-on" \
#     --apple-id "you@example.com" --team-id "RJL9XWBZ9L" --password "app-specific-password"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/pkg/build"
OUTPUT_DIR="$PROJECT_DIR/pkg/dist"
VERSION="1.0.1"
IDENTIFIER="com.autonomath.hdr-always-on"
SIGNING_IDENTITY_APP="Developer ID Application: Mathieu Gagnon (RJL9XWBZ9L)"
SIGNING_IDENTITY_INSTALLER="Developer ID Installer: Mathieu Gagnon (RJL9XWBZ9L)"

NOTARIZE=""
NOTARY_PROFILE=""
if [ "$1" = "--notarize" ] && [ -n "$2" ]; then
    NOTARIZE=1
    NOTARY_PROFILE="$2"
fi

echo "Building hdr-always-on.pkg v$VERSION..."

# Clean
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR/payload/scripts" "$BUILD_DIR/payload/resources" "$OUTPUT_DIR"

# --- Payload ---
# Read source files to embed them in the postinstall script
ENABLE_HDR_B64="$(base64 < "$PROJECT_DIR/enable-hdr.sh")"
PLIST_B64="$(base64 < "$PROJECT_DIR/com.user.enable-hdr.plist")"

cp "$PROJECT_DIR/enable-hdr.sh" "$BUILD_DIR/payload/resources/"
cp "$PROJECT_DIR/com.user.enable-hdr.plist" "$BUILD_DIR/payload/resources/"

# --- postinstall script ---
# Files are embedded as base64 so the nopayload pkg is fully self-contained.
cat > "$BUILD_DIR/payload/scripts/postinstall" << POSTINSTALL
#!/bin/bash
set -e

INSTALL_DIR="\$HOME/.local/bin"
PLIST_DIR="\$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.enable-hdr"

mkdir -p "\$INSTALL_DIR"
mkdir -p "\$PLIST_DIR"

# Decode embedded files
echo "$ENABLE_HDR_B64" | base64 -d > "\$INSTALL_DIR/enable-hdr.sh"
chmod +x "\$INSTALL_DIR/enable-hdr.sh"

echo "$PLIST_B64" | base64 -d | sed "s|__SCRIPT_PATH__|\$INSTALL_DIR/enable-hdr.sh|g" \
    > "\$PLIST_DIR/\$PLIST_NAME.plist"

launchctl unload "\$PLIST_DIR/\$PLIST_NAME.plist" 2>/dev/null || true
launchctl load "\$PLIST_DIR/\$PLIST_NAME.plist"

exit 0
POSTINSTALL
chmod +x "$BUILD_DIR/payload/scripts/postinstall"

# --- Build component pkg ---
# We use a nopayload pkg (just scripts) since we install to user-specific paths
pkgbuild \
    --nopayload \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --scripts "$BUILD_DIR/payload/scripts" \
    "$BUILD_DIR/component.pkg"

# --- Build product archive with resources ---
cat > "$BUILD_DIR/distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>HDR Always On</title>
    <welcome file="welcome.html"/>
    <conclusion file="conclusion.html"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <domains enable_localSystem="false" enable_currentUserHome="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="$IDENTIFIER"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$IDENTIFIER" visible="false">
        <pkg-ref id="$IDENTIFIER"/>
    </choice>
    <pkg-ref id="$IDENTIFIER"
             version="$VERSION"
             onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
EOF

# Welcome page
cat > "$BUILD_DIR/payload/resources/welcome.html" << 'HTML'
<html>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px;">
<h2>HDR Always On</h2>
<p>This will install a lightweight background service that keeps HDR enabled on your external displays.</p>
<p><strong>What gets installed:</strong></p>
<ul>
<li>A small script at <code>~/.local/bin/enable-hdr.sh</code></li>
<li>A LaunchAgent that runs it at login and every 15 minutes</li>
</ul>
<p>No apps, no menu bar icons, no CPU usage. The check takes milliseconds and only acts when HDR is off.</p>
</body>
</html>
HTML

# Conclusion page
cat > "$BUILD_DIR/payload/resources/conclusion.html" << 'HTML'
<html>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px;">
<h2>Installation Complete</h2>
<p>HDR is now being kept on for all your external displays.</p>
<p><strong>To verify:</strong></p>
<pre>tail -f /tmp/enable-hdr.log</pre>
<p><strong>To uninstall:</strong></p>
<pre>curl -fsSL https://raw.githubusercontent.com/autonomath/hdr-always-on/main/uninstall.sh | bash</pre>
</body>
</html>
HTML

# Build the product archive
productbuild \
    --distribution "$BUILD_DIR/distribution.xml" \
    --package-path "$BUILD_DIR" \
    --resources "$BUILD_DIR/payload/resources" \
    "$BUILD_DIR/hdr-always-on-unsigned.pkg"

# --- Sign ---
# Try installer identity first, fall back to unsigned
if security find-identity -v | grep -q "Developer ID Installer"; then
    echo "Signing with: $SIGNING_IDENTITY_INSTALLER"
    productsign \
        --sign "$SIGNING_IDENTITY_INSTALLER" \
        "$BUILD_DIR/hdr-always-on-unsigned.pkg" \
        "$OUTPUT_DIR/hdr-always-on-$VERSION.pkg"
    echo "Signed package: $OUTPUT_DIR/hdr-always-on-$VERSION.pkg"
else
    echo "WARNING: No 'Developer ID Installer' certificate found."
    echo "To sign .pkg files, create one at https://developer.apple.com/account/resources/certificates"
    echo "Building unsigned package..."
    cp "$BUILD_DIR/hdr-always-on-unsigned.pkg" "$OUTPUT_DIR/hdr-always-on-$VERSION.pkg"
    echo "Unsigned package: $OUTPUT_DIR/hdr-always-on-$VERSION.pkg"
fi

# --- Notarize ---
if [ -n "$NOTARIZE" ]; then
    echo "Submitting for notarization..."
    xcrun notarytool submit "$OUTPUT_DIR/hdr-always-on-$VERSION.pkg" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$OUTPUT_DIR/hdr-always-on-$VERSION.pkg"

    echo "Notarized and stapled: $OUTPUT_DIR/hdr-always-on-$VERSION.pkg"
else
    echo ""
    echo "To notarize, run:"
    echo "  xcrun notarytool submit $OUTPUT_DIR/hdr-always-on-$VERSION.pkg --keychain-profile PROFILE --wait"
    echo "  xcrun stapler staple $OUTPUT_DIR/hdr-always-on-$VERSION.pkg"
fi

echo ""
echo "Done!"
