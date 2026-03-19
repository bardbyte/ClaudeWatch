#!/bin/bash
set -euo pipefail

APP_NAME="ClaudeWatch"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

SDK_PATH=$(xcrun --show-sdk-path)

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Build for arm64
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-arm64" \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -swift-version 5 \
    -O \
    Sources/*.swift

# Build for x86_64 (Intel Macs)
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-x86_64" \
    -sdk "$SDK_PATH" \
    -target x86_64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -swift-version 5 \
    -O \
    Sources/*.swift

# Create universal binary
lipo -create \
    "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-arm64" \
    "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-x86_64" \
    -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-arm64"
rm "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-x86_64"

# Copy Info.plist
cp Resources/Info.plist "$APP_BUNDLE/Contents/"

# Clean macOS metadata
find "$BUILD_DIR" -name '.DS_Store' -delete 2>/dev/null || true
xattr -rc "$APP_BUNDLE" 2>/dev/null || true

# Ad-hoc code sign with hardened runtime
codesign --force --sign - --options runtime "$APP_BUNDLE"

echo ""
echo "Built successfully: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
