#!/bin/bash
# download_models.sh
# Script to download Kokoro TTS model files from HuggingFace

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$PROJECT_DIR/Resources"

echo "🎙️ Kokoro Voice Model Downloader"
echo "================================"
echo ""

# Check for git-lfs
if ! command -v git-lfs &> /dev/null; then
    echo "⚠️  git-lfs is required but not installed."
    echo "Install with: brew install git-lfs"
    echo "Then run: git lfs install"
    exit 1
fi

# Create directories
echo "📁 Creating directories..."
mkdir -p "$RESOURCES_DIR/voices"

# Check if model already exists
if [ -f "$RESOURCES_DIR/kokoro-v1_0.safetensors" ]; then
    echo "✓ Model file already exists"
else
    echo "📥 Downloading Kokoro model..."
    echo "   (This may take a while, ~600MB)"

    # Clone the model repo (sparse checkout for just the model file)
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    git clone --filter=blob:none --sparse https://huggingface.co/prince-canuma/Kokoro-82M
    cd Kokoro-82M
    git sparse-checkout set kokoro-v1_0.safetensors
    git lfs pull

    # Copy model file
    cp kokoro-v1_0.safetensors "$RESOURCES_DIR/"

    # Cleanup
    cd "$PROJECT_DIR"
    rm -rf "$TEMP_DIR"

    echo "✓ Model downloaded"
fi

# Download voice files
echo ""
echo "📥 Downloading voice files..."

VOICES=(
    "af_alloy" "af_aoede" "af_bella" "af_heart" "af_jessica"
    "af_kore" "af_nicole" "af_nova" "af_river" "af_sarah" "af_sky"
    "am_adam" "am_echo" "am_michael"
    "bf_alice" "bf_emma"
    "bm_daniel" "bm_george"
)

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

git clone --filter=blob:none --sparse https://huggingface.co/hexgrad/Kokoro-82M
cd Kokoro-82M
git sparse-checkout set voices
git lfs pull

# Copy voice files
for voice in "${VOICES[@]}"; do
    if [ -f "voices/${voice}.pt" ]; then
        cp "voices/${voice}.pt" "$RESOURCES_DIR/voices/"
        echo "  ✓ ${voice}.pt"
    else
        echo "  ⚠️ ${voice}.pt not found"
    fi
done

# Cleanup
cd "$PROJECT_DIR"
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Download complete!"
echo ""
echo "Model files location: $RESOURCES_DIR"
echo ""
echo "Next steps:"
echo "1. Add the Resources folder to your Xcode project"
echo "2. Ensure files are added to both targets"
echo "3. Build and run the app"
