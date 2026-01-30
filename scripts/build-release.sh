#!/bin/bash
# build-release.sh
# Build KokoroVoice for unsigned distribution
# No Apple Developer account required

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/Release"
DIST_DIR="$PROJECT_DIR/dist"

echo "Building KokoroVoice (Unsigned Release)"
echo "========================================"
echo ""

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "Error: xcodegen is required but not installed."
    echo "Install with: brew install xcodegen"
    exit 1
fi

# Check for xcodebuild
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode command line tools are required."
    echo "Install with: xcode-select --install"
    exit 1
fi

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Generate Xcode project with unsigned configuration
echo "Generating Xcode project (unsigned)..."
cd "$PROJECT_DIR"
xcodegen generate --spec project-unsigned.yml

# Build the app
echo ""
echo "Building KokoroVoice..."
xcodebuild \
    -project KokoroVoice.xcodeproj \
    -scheme KokoroVoice \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/build/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    clean build 2>&1 | while read line; do
        # Show progress without too much noise
        if [[ "$line" == *"Build Succeeded"* ]]; then
            echo "$line"
        elif [[ "$line" == *"error:"* ]]; then
            echo "$line"
        elif [[ "$line" == *"warning:"* ]] && [[ "$line" != *"deprecated"* ]]; then
            echo "$line"
        elif [[ "$line" == *"Compiling"* ]]; then
            echo -n "."
        fi
    done
echo ""

# Find and copy the built app
APP_PATH=$(find "$PROJECT_DIR/build/DerivedData" -name "KokoroVoice.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Build failed - KokoroVoice.app not found"
    exit 1
fi

echo "Copying app to dist..."
cp -R "$APP_PATH" "$DIST_DIR/"

# Copy install script
cp "$SCRIPT_DIR/install.sh" "$DIST_DIR/"
chmod +x "$DIST_DIR/install.sh"

# Copy download script
cp "$SCRIPT_DIR/download-models.sh" "$DIST_DIR/"
chmod +x "$DIST_DIR/download-models.sh"

# Check if models exist in Resources
MODEL_FILE="$PROJECT_DIR/Resources/kokoro-v1_0.safetensors"
VOICES_DIR="$PROJECT_DIR/Resources/voices"

if [ -f "$MODEL_FILE" ] && [ -d "$VOICES_DIR" ]; then
    echo "Models found - copying to app bundle..."

    RESOURCES_DEST="$DIST_DIR/KokoroVoice.app/Contents/Resources"
    mkdir -p "$RESOURCES_DEST/voices"

    cp "$MODEL_FILE" "$RESOURCES_DEST/"
    cp "$VOICES_DIR"/*.safetensors "$RESOURCES_DEST/voices/" 2>/dev/null || true
    cp "$VOICES_DIR"/*.pt "$RESOURCES_DEST/voices/" 2>/dev/null || true

    echo "Models embedded in app bundle"
else
    echo ""
    echo "Note: Model files not found in Resources/"
    echo "Users will need to run download-models.sh before using the app"
fi

# Create version info
echo "1.0.0" > "$DIST_DIR/VERSION"
date "+%Y-%m-%d %H:%M:%S" > "$DIST_DIR/BUILD_DATE"

echo ""
echo "Build complete!"
echo ""
echo "Output: $DIST_DIR/"
ls -la "$DIST_DIR/"
echo ""
echo "Next steps:"
echo "1. Test locally: cd $DIST_DIR && ./install.sh"
echo "2. Create DMG: ./scripts/create-dmg.sh"
