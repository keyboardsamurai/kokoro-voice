#!/bin/bash
# create-dmg.sh
# Package KokoroVoice into a distributable DMG

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="KokoroVoice"
VERSION=$(cat "$DIST_DIR/VERSION" 2>/dev/null || echo "1.0.0")
DMG_FILENAME="${DMG_NAME}-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_FILENAME"

echo ""
echo "Creating KokoroVoice DMG"
echo "========================"
echo ""

# Check if dist directory exists
if [ ! -d "$DIST_DIR" ]; then
    echo "Error: dist/ directory not found"
    echo "Run 'make release' first to build the app"
    exit 1
fi

# Check if app exists
if [ ! -d "$DIST_DIR/KokoroVoice.app" ]; then
    echo "Error: KokoroVoice.app not found in dist/"
    echo "Run 'make release' first to build the app"
    exit 1
fi

# Remove existing DMG
if [ -f "$DMG_PATH" ]; then
    echo "Removing existing DMG..."
    rm -f "$DMG_PATH"
fi

# Create a temporary directory for DMG contents
DMG_TEMP="$PROJECT_DIR/build/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

echo "Preparing DMG contents..."

# Copy app
cp -R "$DIST_DIR/KokoroVoice.app" "$DMG_TEMP/"

# Copy installer script
cp "$DIST_DIR/install.sh" "$DMG_TEMP/"
chmod +x "$DMG_TEMP/install.sh"

# Copy download script (in case models aren't bundled)
cp "$DIST_DIR/download-models.sh" "$DMG_TEMP/"
chmod +x "$DMG_TEMP/download-models.sh"

# Create README for the DMG
cat > "$DMG_TEMP/README.txt" << 'EOF'
KokoroVoice - Neural TTS for macOS
==================================

KokoroVoice provides high-quality neural text-to-speech voices
for macOS using the Kokoro TTS model.

INSTALLATION
------------

Option 1: Easy Install (Recommended)
  1. Open Terminal
  2. Drag install.sh into the Terminal window
  3. Press Enter and follow the prompts

Option 2: Manual Install
  1. Drag KokoroVoice.app to your Applications folder
  2. Right-click the app and select "Open" (bypasses Gatekeeper)
  3. Go to System Settings > Privacy & Security
  4. Click "Open Anyway" if prompted

FIRST RUN
---------

1. Launch KokoroVoice from Applications
2. Wait for the model to load (may take 30-60 seconds first time)
3. Enable voices in System Settings > Accessibility > Spoken Content

REQUIREMENTS
------------

- macOS 15.0 (Sequoia) or later
- Apple Silicon (M1/M2/M3/M4)
- ~500MB disk space

TROUBLESHOOTING
---------------

If voices don't appear in System Settings:
  - Log out and log back in
  - Or run in Terminal: sudo killall -9 speechsynthesisd

For more help, visit:
https://github.com/YOUR_USERNAME/kokorovoice

LICENSE
-------

This software uses the Kokoro TTS model.
See the included LICENSE file for details.
EOF

# Create Applications symlink for drag-and-drop install
ln -s /Applications "$DMG_TEMP/Applications"

# Check model size to set appropriate DMG size
MODEL_SIZE=0
if [ -f "$DMG_TEMP/KokoroVoice.app/Contents/Resources/kokoro-v1_0.safetensors" ]; then
    MODEL_SIZE=$(du -sm "$DMG_TEMP/KokoroVoice.app/Contents/Resources" | cut -f1)
fi

# Calculate DMG size (contents + 20% overhead, minimum 100MB)
CONTENTS_SIZE=$(du -sm "$DMG_TEMP" | cut -f1)
DMG_SIZE=$((CONTENTS_SIZE + CONTENTS_SIZE / 5 + 50))
[ $DMG_SIZE -lt 100 ] && DMG_SIZE=100

echo "Creating DMG (${DMG_SIZE}MB)..."

# Create DMG
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# Clean up
rm -rf "$DMG_TEMP"

# Get final size
FINAL_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "DMG created successfully!"
echo ""
echo "  File: $DMG_PATH"
echo "  Size: $FINAL_SIZE"
echo ""
echo "The DMG contains:"
echo "  - KokoroVoice.app"
echo "  - install.sh (easy installer)"
echo "  - download-models.sh (if models not bundled)"
echo "  - README.txt"
echo "  - Applications shortcut"

# Check if models are included
if [ -f "$DIST_DIR/KokoroVoice.app/Contents/Resources/kokoro-v1_0.safetensors" ]; then
    echo ""
    echo "Note: Model files are included in the app bundle."
else
    echo ""
    echo "Note: Model files are NOT included."
    echo "Users will need to run download-models.sh after installation."
fi

echo ""
