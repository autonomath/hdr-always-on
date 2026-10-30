#!/bin/bash
# Build the universal hdr-always-on binary (Apple silicon and Intel).
#
# Usage:
#   ./build.sh                 # Writes bin/hdr-always-on
#   ./build.sh OUTPUT_PATH     # Writes the binary somewhere else
#
# Requires Xcode or the Command Line Tools. The binary is ad hoc signed unless
# SIGN_IDENTITY names a Developer ID Application certificate.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$PROJECT_DIR/bin/hdr-always-on}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
MIN_MACOS="11.0"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

for arch in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 \
        -target "$arch-apple-macos$MIN_MACOS" \
        -o "$WORK_DIR/hdr-always-on-$arch" \
        "$PROJECT_DIR/src/main.swift"
done

mkdir -p "$(dirname "$OUTPUT")"
lipo -create -output "$OUTPUT" "$WORK_DIR/hdr-always-on-arm64" "$WORK_DIR/hdr-always-on-x86_64"

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$OUTPUT"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT"
fi
codesign --verify --strict "$OUTPUT"

echo "Built $OUTPUT ($(lipo -archs "$OUTPUT"))"
