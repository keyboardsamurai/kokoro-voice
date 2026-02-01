# Kokoro Voice - macOS Speech Synthesis Provider

A macOS Speech Synthesis Provider extension that integrates the [Kokoro TTS](https://huggingface.co/hexgrad/Kokoro-82M) neural network model as a system-level voice, making Kokoro's high-quality voices available to VoiceOver, Spoken Content, Live Speech, and any application using `AVSpeechSynthesizer`.

## Features

- **18 High-Quality Neural Voices** - American and British English, male and female
- **System-Level Integration** - Works with VoiceOver, Spoken Content, and all apps
- **On-Device Processing** - No internet required, powered by Apple MLX
- **SSML Support** - Handles prosody (rate), breaks, and more
- **Native SwiftUI App** - Clean interface for managing voices

## Requirements

- **macOS 15.0+** (Sequoia) - Required for MLX Swift
- **Apple Silicon** (M1/M2/M3/M4) - Required for MLX framework
- **Xcode 15.0+** (for building from source)

## Installation

**For pre-built binaries**, see [INSTALL.md](INSTALL.md) for easy installation instructions.

**To build from source**, continue reading below.

## Quick Start (Build from Source)

```bash
# 1. Download model files (~326MB, first time only)
make download-models

# 2. Build unsigned release
make release

# 3. Install locally
make install
```

Or create a distributable DMG:

```bash
make dist
```

## Project Structure

```
KokoroVoice/
├── Makefile                       # Build commands
├── project.yml                    # XcodeGen project specification (signed)
├── project-unsigned.yml           # XcodeGen project specification (unsigned)
├── Package.swift                  # SPM for testing components
├── INSTALL.md                     # End-user installation guide
├── scripts/
│   ├── build-release.sh           # Build unsigned app
│   ├── download-models.sh         # Download model files
│   ├── install.sh                 # Local installation
│   └── create-dmg.sh              # Create distributable DMG
├── KokoroVoice/                   # Host App
│   ├── KokoroVoiceApp.swift       # Main app entry
│   ├── ContentView.swift          # Main UI
│   ├── VoiceManager.swift         # Voice state management
│   ├── Info.plist
│   └── KokoroVoice.entitlements
├── KokoroVoiceExtension/          # Audio Unit Extension
│   ├── KokoroSynthesisAudioUnit.swift  # Main AU class
│   ├── SSMLParser.swift           # SSML parsing
│   ├── Info.plist
│   └── KokoroVoiceExtension.entitlements
├── Shared/                        # Shared Code
│   ├── Constants.swift            # App constants
│   ├── VoiceConfiguration.swift   # Voice config model
│   └── KokoroEngine.swift         # TTS engine wrapper
├── Tests/                         # Unit Tests
│   ├── SSMLParserTests/
│   ├── VoiceConfigurationTests/
│   └── KokoroEngineTests/
└── Resources/                     # Model files (when downloaded)
    ├── kokoro-v1_0.safetensors
    └── voices/
        ├── af_heart.pt
        └── ...
```

## Developer Setup

For development with code signing and debugging in Xcode:

### Prerequisites

```bash
# Install XcodeGen
brew install xcodegen
```

### Download Models

Model files (~326MB) are not included in the repository. Download them using:

```bash
make download-models
# or directly:
./scripts/download-models.sh
```

### Generate Xcode Project

For signed development builds:

```bash
xcodegen generate
open KokoroVoice.xcodeproj
```

For unsigned builds:

```bash
xcodegen generate --spec project-unsigned.yml
open KokoroVoice.xcodeproj
```

### Configure Signing (Signed builds only)

1. Select the project in Xcode
2. For each target, select your Development Team
3. Xcode will manage signing automatically

### Apple Developer Setup (Signed builds only)

1. **Register App IDs** (developer.apple.com):
   - `com.kokorovoice.app` (host app)
   - `com.kokorovoice.app.extension` (extension)

2. **Register App Group**:
   - `group.com.kokorovoice.shared`

3. **Create Provisioning Profiles**:
   - Include App Groups capability for both profiles

## Running Tests

```bash
# Using Swift Package Manager
cd KokoroVoice
swift test

# Using Xcode
# Cmd+U or Product → Test
```

## Usage

1. **Launch KokoroVoice app**
2. **Enable desired voices** using the toggles
3. **Wait ~30 seconds** for system registration
4. **Open System Settings**:
   - Accessibility → Spoken Content → System Voice
   - Select a Kokoro voice

### Testing Voices

- Click the play button next to any voice to hear a sample
- Use the test panel at the bottom to speak custom text
- Voices can be tested even before enabling for system use

## Troubleshooting

### Voices Don't Appear in System Settings

1. Ensure at least one voice is enabled in the app
2. Wait 30 seconds for registration
3. Try restarting the app
4. Run in Terminal:
   ```bash
   sudo killall -9 speechsynthesisd
   ```

### Audio Unit Not Loading

Check registration:
```bash
auval -a | grep KOKO
pluginkit -m | grep KokoroVoice
```

### Model Load Errors

1. Verify model files exist in Resources
2. Check Console.app for detailed errors:
   ```bash
   log stream --predicate 'subsystem contains "kokorovoice"'
   ```

## Available Voices

| Voice ID | Name | Language | Gender |
|----------|------|----------|--------|
| af_heart | Kokoro Heart | en-US | Female |
| af_bella | Kokoro Bella | en-US | Female |
| af_nova | Kokoro Nova | en-US | Female |
| am_adam | Kokoro Adam | en-US | Male |
| am_michael | Kokoro Michael | en-US | Male |
| bf_alice | Kokoro Alice | en-GB | Female |
| bm_daniel | Kokoro Daniel | en-GB | Male |
| ... | ... | ... | ... |

See `Shared/Constants.swift` for the complete list.

## SSML Support

| Element | Supported | Example |
|---------|-----------|---------|
| `<speak>` | ✅ | `<speak>Hello world</speak>` |
| `<prosody rate>` | ✅ | `<prosody rate="150%">Fast</prosody>` |
| `<break time>` | ✅ | `<break time="1s"/>` |
| `<break strength>` | ✅ | `<break strength="strong"/>` |
| `<p>` | ✅ | Paragraph pause |
| `<s>` | ✅ | Sentence pause |

### SSML Best Practices for Optimal Latency

For the best experience with long texts, structure your SSML with natural breaks. This allows audio to start playing within 500ms regardless of total text length:

- **Use `<s>` tags around sentences** - Each sentence becomes a separate chunk
- **Use `<p>` tags around paragraphs** - Adds natural pauses between sections
- **Avoid single segments longer than ~50 words** - Very long segments delay first audio

**Example - Well-structured SSML:**
```xml
<speak>
  <p>
    <s>Welcome to the presentation.</s>
    <s>Today we will discuss neural text-to-speech technology.</s>
  </p>
  <p>
    <s>Kokoro uses advanced machine learning to generate natural-sounding speech.</s>
    <s>The model runs entirely on-device using Apple's MLX framework.</s>
  </p>
</speak>
```

## Architecture

```
┌─────────────────────────────────────────┐
│          macOS System                    │
│  VoiceOver / Spoken Content / Apps       │
└──────────────────┬──────────────────────┘
                   │ AVSpeechSynthesizer
                   ▼
┌─────────────────────────────────────────┐
│        KokoroVoice.app                   │
│  ┌───────────────────────────────────┐  │
│  │     KokoroVoiceExtension.appex    │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │ KokoroSynthesisAudioUnit    │  │  │
│  │  │    ↓ SSML → SSMLParser      │  │  │
│  │  │    ↓ Text → KokoroEngine    │  │  │
│  │  │    ↓ Audio → RenderBlock    │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## License

This implementation uses:
- **Kokoro TTS** - Apache 2.0 License (hexgrad)
- **KokoroSwift** - MIT License (mlalma)
- **MLX Swift** - MIT License (Apple)

## Contributing

1. Fork the repository
2. Create your feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## References

- [WWDC23: Extend Speech Synthesis](https://developer.apple.com/videos/play/wwdc2023/10033/)
- [AVSpeechSynthesisProviderAudioUnit Documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovideraudiounit)
- [KokoroSwift Package](https://github.com/mlalma/kokoro-ios)
- [Kokoro Model on HuggingFace](https://huggingface.co/hexgrad/Kokoro-82M)
