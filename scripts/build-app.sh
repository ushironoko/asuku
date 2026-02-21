#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="asuku.app"
APP_DIR="$BUILD_DIR/$APP_NAME"

# Defaults
CONFIGURATION="debug"
UNIVERSAL=false
VERSION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            CONFIGURATION="release"
            shift
            ;;
        --universal)
            UNIVERSAL=true
            shift
            ;;
        --version)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --version requires a value (e.g., --version 1.0.0)"
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--release] [--universal] [--version <version>]"
            echo ""
            echo "Options:"
            echo "  --release          Build in release configuration"
            echo "  --universal        Build Universal Binary (arm64 + x86_64)"
            echo "  --version <ver>    Set CFBundleShortVersionString and CFBundleVersion"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Build arguments
BUILD_ARGS=(--package-path "$PROJECT_DIR" -c "$CONFIGURATION")
if $UNIVERSAL; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

# Get binary output path before building (avoids second swift build invocation)
BIN_PATH=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)

echo "Building ($CONFIGURATION$(${UNIVERSAL} && echo ', universal' || true))..."
swift build "${BUILD_ARGS[@]}"

echo "Assembling $APP_NAME..."

# Clean previous bundle
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/AsukuApp/Info.plist" "$APP_DIR/Contents/Info.plist"

# Inject version into Info.plist
if [ -n "$VERSION" ]; then
    echo "Setting version to $VERSION..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"
fi

# Copy binaries
cp "$BIN_PATH/AsukuApp" "$APP_DIR/Contents/MacOS/AsukuApp"
cp "$BIN_PATH/asuku-hook" "$APP_DIR/Contents/MacOS/asuku-hook"

# Strip debug symbols in release mode
if [ "$CONFIGURATION" = "release" ]; then
    echo "Stripping debug symbols..."
    strip -x "$APP_DIR/Contents/MacOS/AsukuApp"
    strip -x "$APP_DIR/Contents/MacOS/asuku-hook"
fi

# Copy app icon
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code sign (inside-out, --deep is deprecated by Apple)
echo "Code signing..."
codesign --force --sign - "$APP_DIR/Contents/MacOS/asuku-hook"
codesign --force --sign - "$APP_DIR"

echo "Done: $APP_DIR"
echo ""
echo "Run with:"
echo "  open $APP_DIR"
echo ""
echo "Or directly:"
echo "  $APP_DIR/Contents/MacOS/AsukuApp"
