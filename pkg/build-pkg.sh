#!/bin/bash
# Build the hdr-always-on .pkg installer, signing and notarizing it when asked.
#
# Usage:
#   ./pkg/build-pkg.sh                     # Build, signing with Developer ID certificates when available
#   ./pkg/build-pkg.sh --unsigned          # Build without signing
#   ./pkg/build-pkg.sh --notarize PROFILE  # Build, sign, and notarize
#
# Before notarizing, store credentials once:
#   xcrun notarytool store-credentials "hdr-always-on" \
#     --apple-id "you@example.com" --team-id "RJL9XWBZ9L" --password "app-specific-password"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/dist"
VERSION="$(sed -n 's/^let appVersion = "\(.*\)"$/\1/p' "$PROJECT_DIR/src/main.swift")"
IDENTIFIER="com.autonomath.hdr-always-on"
LABEL="com.autonomath.hdr-always-on"
APP_IDENTITY="Developer ID Application: Mathieu Gagnon (RJL9XWBZ9L)"
INSTALLER_IDENTITY="Developer ID Installer: Mathieu Gagnon (RJL9XWBZ9L)"
PKG="$OUTPUT_DIR/hdr-always-on-$VERSION.pkg"

SIGN=1
NOTARY_PROFILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --unsigned) SIGN=0; shift ;;
        --notarize) NOTARY_PROFILE="${2:?--notarize needs a keychain profile name}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 64 ;;
    esac
done

has_identity() {
    security find-identity -v | grep -qF "\"$1\""
}

echo "Building hdr-always-on.pkg v$VERSION..."

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR/scripts" "$BUILD_DIR/resources" "$OUTPUT_DIR"

# --- Installer scripts folder: the postinstall plus the files it installs ---
if [ "$SIGN" -eq 1 ] && has_identity "$APP_IDENTITY"; then
    echo "Signing the binary with: $APP_IDENTITY"
    SIGN_IDENTITY="$APP_IDENTITY" "$PROJECT_DIR/build.sh" "$BUILD_DIR/scripts/hdr-always-on"
else
    "$PROJECT_DIR/build.sh" "$BUILD_DIR/scripts/hdr-always-on"
fi
cp "$PROJECT_DIR/$LABEL.plist" "$BUILD_DIR/scripts/"
cp "$SCRIPT_DIR/postinstall" "$BUILD_DIR/scripts/postinstall"
chmod 755 "$BUILD_DIR/scripts/postinstall"

# A nopayload package (scripts only), because everything installs into the user's home folder.
pkgbuild \
    --nopayload \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --scripts "$BUILD_DIR/scripts" \
    "$BUILD_DIR/component.pkg"

# --- Product archive ---
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

cat > "$BUILD_DIR/resources/welcome.html" << 'HTML'
<html>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px;">
<h2>HDR Always On</h2>
<p>This installs a small background helper that turns HDR back on for your external displays when macOS switches it off.</p>
<p><strong>What gets installed:</strong></p>
<ul>
<li>The helper at <code>~/.local/bin/hdr-always-on</code></li>
<li>A LaunchAgent that starts it when you log in</li>
</ul>
<p>It checks after wake, unlock, and display changes, and every 15 minutes, and uses no CPU in between.</p>
</body>
</html>
HTML

cat > "$BUILD_DIR/resources/conclusion.html" << 'HTML'
<html>
<body style="font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px;">
<h2>Installation Complete</h2>
<p>HDR will now be kept on for your external displays.</p>
<p><strong>See your displays and their HDR state:</strong></p>
<pre>~/.local/bin/hdr-always-on list</pre>
<p><strong>Leave a display alone:</strong></p>
<pre>~/.local/bin/hdr-always-on exclude "DISPLAY NAME"</pre>
<p><strong>Log:</strong></p>
<pre>tail -f ~/Library/Logs/hdr-always-on.log</pre>
<p><strong>To uninstall:</strong></p>
<pre>curl -fsSL https://raw.githubusercontent.com/autonomath/hdr-always-on/main/uninstall.sh | bash</pre>
</body>
</html>
HTML

productbuild \
    --distribution "$BUILD_DIR/distribution.xml" \
    --package-path "$BUILD_DIR" \
    --resources "$BUILD_DIR/resources" \
    "$BUILD_DIR/hdr-always-on-unsigned.pkg"

# --- Sign ---
SIGNED_PKG=0
if [ "$SIGN" -eq 1 ] && has_identity "$INSTALLER_IDENTITY"; then
    echo "Signing the package with: $INSTALLER_IDENTITY"
    productsign --sign "$INSTALLER_IDENTITY" "$BUILD_DIR/hdr-always-on-unsigned.pkg" "$PKG"
    SIGNED_PKG=1
else
    if [ "$SIGN" -eq 1 ]; then
        echo "No '$INSTALLER_IDENTITY' certificate found, so the package is unsigned."
        echo "Create one at https://developer.apple.com/account/resources/certificates"
    fi
    cp "$BUILD_DIR/hdr-always-on-unsigned.pkg" "$PKG"
fi
echo "Package: $PKG"

# --- Notarize ---
if [ -n "$NOTARY_PROFILE" ]; then
    if [ "$SIGNED_PKG" -ne 1 ]; then
        echo "Notarization needs a signed package." >&2
        exit 1
    fi
    echo "Submitting for notarization..."
    xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$PKG"
    echo "Notarized and stapled: $PKG"
fi

echo "Done!"
