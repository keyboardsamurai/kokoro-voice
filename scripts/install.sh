#!/bin/bash
# install.sh
# One-command installer for KokoroVoice
# Handles Gatekeeper bypass, system checks, and installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="KokoroVoice.app"
APP_PATH="$SCRIPT_DIR/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

echo ""
echo "KokoroVoice Installer"
echo "====================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_ok() { echo -e "${GREEN}[ok]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
print_error() { echo -e "${RED}[error]${NC} $1"; }
print_info() { echo "     $1"; }

# Check macOS version (requires 15.0+)
echo "Checking system requirements..."
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)

if [ "$MACOS_MAJOR" -lt 15 ]; then
    print_error "macOS 15.0 (Sequoia) or later is required"
    print_info "Your version: macOS $MACOS_VERSION"
    exit 1
fi
print_ok "macOS $MACOS_VERSION"

# Check for Apple Silicon
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    print_error "Apple Silicon (M1/M2/M3/M4) is required"
    print_info "Your architecture: $ARCH"
    exit 1
fi
print_ok "Apple Silicon ($ARCH)"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    print_error "KokoroVoice.app not found in current directory"
    print_info "Expected: $APP_PATH"
    exit 1
fi
print_ok "Found $APP_NAME"

# Check if models are present
MODEL_FILE="$APP_PATH/Contents/Resources/kokoro-v1_0.safetensors"
VOICES_DIR="$APP_PATH/Contents/Resources/voices"

if [ ! -f "$MODEL_FILE" ]; then
    print_warn "Model files not found in app bundle"
    echo ""
    echo "Would you like to download them now? (~326MB)"
    read -p "Download models? [Y/n] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ -f "$SCRIPT_DIR/download-models.sh" ]; then
            "$SCRIPT_DIR/download-models.sh"
        else
            print_error "download-models.sh not found"
            exit 1
        fi
    else
        print_warn "Skipping model download - app will not work without models"
    fi
else
    VOICE_COUNT=$(ls -1 "$VOICES_DIR"/*.safetensors 2>/dev/null | wc -l | tr -d ' ')
    print_ok "Model files present ($VOICE_COUNT voices)"
fi

# Remove existing installation
if [ -d "$INSTALL_PATH" ]; then
    echo ""
    echo "Existing installation found at $INSTALL_PATH"
    read -p "Replace it? [Y/n] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi

    echo "Removing existing installation..."
    rm -rf "$INSTALL_PATH"
fi

# Remove quarantine attribute (Gatekeeper bypass for unsigned app)
echo ""
echo "Removing Gatekeeper quarantine attributes..."
xattr -cr "$APP_PATH" 2>/dev/null || true
print_ok "Quarantine attributes removed"

# Copy to Applications
echo ""
echo "Installing to /Applications..."
cp -R "$APP_PATH" "$INSTALL_PATH"

if [ ! -d "$INSTALL_PATH" ]; then
    print_error "Failed to copy app to /Applications"
    print_info "Try running with sudo: sudo ./install.sh"
    exit 1
fi

# Remove quarantine from installed copy too
xattr -cr "$INSTALL_PATH" 2>/dev/null || true

print_ok "Installed to $INSTALL_PATH"

# Register the extension
echo ""
echo "Registering speech synthesis extension..."

# Force the system to recognize the new extension
pluginkit -a "$INSTALL_PATH/Contents/PlugIns/KokoroVoiceExtension.appex" 2>/dev/null || true

# Reset speech synthesis daemon to pick up new voices
killall speechsynthesisd 2>/dev/null || true

print_ok "Extension registered"

# Verify installation
echo ""
echo "Verifying installation..."

# Give the system a moment to register the extension
sleep 2

# Check if voices are available
if say -v '?' 2>/dev/null | grep -q "Kokoro"; then
    print_ok "Kokoro voices detected by system"
else
    print_warn "Voices not yet detected (this is normal on first install)"
    print_info "Try launching KokoroVoice.app and restart the test"
fi

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Open KokoroVoice from /Applications"
echo "   (First launch may take a moment to load models)"
echo ""
echo "2. Enable voices in System Settings:"
echo "   System Settings > Accessibility > Spoken Content"
echo "   Click 'System Voice' > Manage Voices > English"
echo "   Look for 'Kokoro' voices"
echo ""
echo "3. Test a voice:"
echo "   say -v 'Kokoro Heart (Female)' 'Hello from Kokoro Voice'"
echo ""
echo "If voices don't appear:"
echo "  - Try logging out and back in"
echo "  - Or run: sudo killall -9 speechsynthesisd"
echo ""
