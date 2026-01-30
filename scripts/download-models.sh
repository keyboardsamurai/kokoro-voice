#!/bin/bash
# download-models.sh
# Download Kokoro TTS model files from HuggingFace
# Uses curl for simple, resumable downloads with progress
#
# Models are downloaded in safetensors format for MLX compatibility

set -e

# Determine script location and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running from dist folder or project folder
if [ -d "$SCRIPT_DIR/../KokoroVoice.app" ]; then
    # Running from dist folder - put models in app bundle
    RESOURCES_DIR="$SCRIPT_DIR/KokoroVoice.app/Contents/Resources"
    echo "Installing models to app bundle..."
elif [ -d "$SCRIPT_DIR/../Resources" ]; then
    # Running from project scripts folder
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    RESOURCES_DIR="$PROJECT_DIR/Resources"
    echo "Downloading models to project Resources..."
else
    # Fallback - create Resources directory
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    RESOURCES_DIR="$PROJECT_DIR/Resources"
    mkdir -p "$RESOURCES_DIR"
    echo "Creating Resources directory..."
fi

# HuggingFace base URLs - using mlx-community format for safetensors
HF_MODEL_URL="https://huggingface.co/mlx-community/Kokoro-82M-bf16-mlx/resolve/main"
HF_VOICES_URL="https://huggingface.co/mlx-community/Kokoro-82M-bf16-mlx/resolve/main/voices"

echo ""
echo "Kokoro Voice Model Downloader"
echo "============================="
echo ""
echo "Target: $RESOURCES_DIR"
echo ""

# Create directories
mkdir -p "$RESOURCES_DIR/voices"

# Function to download with progress
download_file() {
    local url="$1"
    local dest="$2"
    local name="$3"

    if [ -f "$dest" ]; then
        local size=$(stat -f%z "$dest" 2>/dev/null || stat -c%s "$dest" 2>/dev/null || echo "0")
        if [ "$size" -gt 1000 ]; then
            echo "  [skip] $name (already exists)"
            return 0
        fi
    fi

    echo "  [download] $name"
    if curl -L --progress-bar -o "$dest.tmp" "$url" 2>/dev/null; then
        mv "$dest.tmp" "$dest"
    else
        rm -f "$dest.tmp"
        echo "  [error] Failed to download $name"
        return 1
    fi

    if [ ! -f "$dest" ]; then
        echo "  [error] Failed to download $name"
        return 1
    fi
}

# Download main model file (~312MB)
echo "Downloading main model (~312MB)..."
download_file \
    "$HF_MODEL_URL/kokoro-v1_0.safetensors" \
    "$RESOURCES_DIR/kokoro-v1_0.safetensors" \
    "kokoro-v1_0.safetensors"

# Also download config.json for model configuration
echo ""
echo "Downloading model config..."
download_file \
    "$HF_MODEL_URL/config.json" \
    "$RESOURCES_DIR/config.json" \
    "config.json"

# Voice files to download (~0.5MB each, ~14MB total)
VOICES=(
    "af_alloy"
    "af_aoede"
    "af_bella"
    "af_heart"
    "af_jessica"
    "af_kore"
    "af_nicole"
    "af_nova"
    "af_river"
    "af_sarah"
    "af_sky"
    "am_adam"
    "am_echo"
    "am_michael"
    "bf_alice"
    "bf_emma"
    "bm_daniel"
    "bm_george"
)

echo ""
echo "Downloading voice files (${#VOICES[@]} voices, ~14MB total)..."

for voice in "${VOICES[@]}"; do
    download_file \
        "$HF_VOICES_URL/${voice}.safetensors" \
        "$RESOURCES_DIR/voices/${voice}.safetensors" \
        "${voice}.safetensors"
done

# Verify downloads
echo ""
echo "Verifying downloads..."

MISSING=0
if [ ! -f "$RESOURCES_DIR/kokoro-v1_0.safetensors" ]; then
    echo "  [missing] kokoro-v1_0.safetensors"
    MISSING=1
else
    echo "  [ok] kokoro-v1_0.safetensors"
fi

VOICE_COUNT=0
for voice in "${VOICES[@]}"; do
    if [ -f "$RESOURCES_DIR/voices/${voice}.safetensors" ]; then
        VOICE_COUNT=$((VOICE_COUNT + 1))
    else
        echo "  [missing] voices/${voice}.safetensors"
        MISSING=1
    fi
done
echo "  [ok] $VOICE_COUNT/${#VOICES[@]} voice files"

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "Some files are missing. Try running the script again."
    echo "If downloads keep failing, check your internet connection."
    exit 1
fi

# Calculate total size
TOTAL_SIZE=$(du -sh "$RESOURCES_DIR" 2>/dev/null | cut -f1)

echo ""
echo "Download complete!"
echo ""
echo "Location: $RESOURCES_DIR"
echo "Total size: $TOTAL_SIZE"
echo ""

# Show next steps based on context
if [ -d "$SCRIPT_DIR/../KokoroVoice.app" ]; then
    echo "Models installed in app bundle."
    echo "Run ./install.sh to complete installation."
else
    echo "Next steps:"
    echo "1. Build the project: make release"
    echo "2. Or add Resources to Xcode project manually"
fi
