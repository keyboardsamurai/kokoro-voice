# Makefile for KokoroVoice
# Build, test, and package commands for unsigned distribution

.PHONY: all setup download-models release install dmg clean help

# Default target
all: help

# Check and install dependencies
setup:
	@echo "Checking dependencies..."
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing xcodegen..."; brew install xcodegen; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "Error: Xcode required. Install from App Store."; exit 1; }
	@echo "Dependencies OK"

# Download model files from HuggingFace
download-models:
	@echo "Downloading Kokoro models..."
	@chmod +x scripts/download-models.sh
	@./scripts/download-models.sh

# Build unsigned release
release: setup
	@echo "Building unsigned release..."
	@chmod +x scripts/build-release.sh
	@./scripts/build-release.sh

# Install locally (for testing)
install: release
	@echo "Installing locally..."
	@chmod +x dist/install.sh
	@cd dist && ./install.sh

# Create DMG for distribution
dmg: release
	@echo "Creating DMG..."
	@chmod +x scripts/create-dmg.sh
	@./scripts/create-dmg.sh

# Full distribution build (with models)
dist: download-models release dmg
	@echo ""
	@echo "Distribution package ready!"
	@ls -la *.dmg 2>/dev/null || echo "No DMG found"

# Generate Xcode project (signed version for development)
xcode:
	@echo "Generating Xcode project (signed)..."
	@xcodegen generate
	@echo "Open KokoroVoice.xcodeproj"

# Generate Xcode project (unsigned version)
xcode-unsigned:
	@echo "Generating Xcode project (unsigned)..."
	@xcodegen generate --spec project-unsigned.yml
	@echo "Open KokoroVoice.xcodeproj"

# Run tests
test:
	@echo "Running tests..."
	@swift test

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf build/
	@rm -rf dist/
	@rm -rf .build/
	@rm -f *.dmg
	@echo "Clean complete"

# Clean everything including models
clean-all: clean
	@echo "Removing downloaded models..."
	@rm -rf Resources/kokoro-v1_0.safetensors
	@rm -rf Resources/voices/
	@rm -rf Resources/config.json
	@echo "Full clean complete"

# Show help
help:
	@echo ""
	@echo "KokoroVoice Build System"
	@echo "========================"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development:"
	@echo "  setup           - Check/install dependencies"
	@echo "  xcode           - Generate signed Xcode project"
	@echo "  xcode-unsigned  - Generate unsigned Xcode project"
	@echo "  test            - Run unit tests"
	@echo ""
	@echo "Distribution:"
	@echo "  download-models - Download model files (~326MB)"
	@echo "  release         - Build unsigned release"
	@echo "  install         - Build and install locally"
	@echo "  dmg             - Create distributable DMG"
	@echo "  dist            - Full distribution (models + build + DMG)"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean           - Remove build artifacts"
	@echo "  clean-all       - Remove everything including models"
	@echo ""
	@echo "Quick start:"
	@echo "  make download-models  # First time only"
	@echo "  make release          # Build the app"
	@echo "  make install          # Install and test"
	@echo ""
