#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="asuku.app"
APP_DIR="$BUILD_DIR/$APP_NAME"

echo "Building..."
swift build --package-path "$PROJECT_DIR"

echo "Assembling $APP_NAME..."

# Clean previous bundle
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/AsukuApp/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy binaries
cp "$BUILD_DIR/debug/AsukuApp" "$APP_DIR/Contents/MacOS/AsukuApp"
cp "$BUILD_DIR/debug/asuku-hook" "$APP_DIR/Contents/MacOS/asuku-hook"

# Copy app icon
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code sign (required for notifications on macOS)
echo "Code signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done: $APP_DIR"
echo ""
echo "Run with:"
echo "  open $APP_DIR"
echo ""
echo "Or directly:"
echo "  $APP_DIR/Contents/MacOS/AsukuApp"
