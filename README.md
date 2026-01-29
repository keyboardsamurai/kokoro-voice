# Kokoro Voice - macOS Speech Synthesis Provider

A macOS Speech Synthesis Provider extension that integrates the [Kokoro TTS](https://huggingface.co/hexgrad/Kokoro-82M) neural network model as a system-level voice, making Kokoro's high-quality voices available to VoiceOver, Spoken Content, Live Speech, and any application using `AVSpeechSynthesizer`.

## Features

- 🎙️ **18 High-Quality Neural Voices** - American and British English, male and female
- 🔊 **System-Level Integration** - Works with VoiceOver, Spoken Content, and all apps
- ⚡ **On-Device Processing** - No internet required, powered by Apple MLX
- 🎚️ **SSML Support** - Handles prosody (rate), breaks, and more
- 🍎 **Native SwiftUI App** - Clean interface for managing voices

## Requirements

- **macOS 15.0+** (Sequoia) - Required for MLX Swift
- **Apple Silicon** (M1/M2/M3/M4) - Required for MLX framework
- **Xcode 15.0+**

## Project Structure

```
KokoroVoice/
├── project.yml                    # XcodeGen project specification
├── Package.swift                  # SPM for testing components
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
└── Resources/                     # Model files (add manually)
    ├── kokoro-v1_0.safetensors
    └── voices/
        ├── af_heart.pt
        └── ...
```

## Setup Instructions

### Option 1: Using XcodeGen (Recommended)

1. **Install XcodeGen**:
   ```bash
   brew install xcodegen
   ```

2. **Generate Xcode Project**:
   ```bash
   cd KokoroVoice
   xcodegen generate
   ```

3. **Open in Xcode**:
   ```bash
   open KokoroVoice.xcodeproj
   ```

4. **Configure Signing**:
   - Select the project in Xcode
   - For each target, select your Development Team
   - Xcode will manage signing automatically

5. **Add Model Files** (see below)

6. **Build and Run**

### Option 2: Manual Xcode Setup

If you prefer not to use XcodeGen:

1. **Create New Project**:
   - File → New → Project → macOS → App
   - Product Name: `KokoroVoice`
   - Team: Select your team
   - Interface: SwiftUI
   - Language: Swift

2. **Add Audio Unit Extension Target**:
   - File → New → Target → Audio Unit Extension
   - Product Name: `KokoroVoiceExtension`
   - **Audio Unit Type: Speech Synthesizer** ⚠️ Critical
   - Subtype: `KVSP`
   - Manufacturer: `KOKO`

3. **Configure App Groups**:
   - Select KokoroVoice target → Signing & Capabilities
   - Add "App Groups" → Create: `group.com.kokorovoice.shared`
   - Repeat for KokoroVoiceExtension target

4. **Add Swift Package**:
   - File → Add Package Dependencies
   - URL: `https://github.com/mlalma/kokoro-ios.git`
   - Add to BOTH targets

5. **Copy Source Files**:
   - Copy all `.swift` files to appropriate targets
   - Copy Info.plist and entitlements files

6. **Add Model Files** (see below)

### Adding Model Files

The model files are not included due to size (~600MB). Download them:

1. **Download Model**:
   ```bash
   # Create Resources directory
   mkdir -p KokoroVoice/Resources/voices

   # Download model (requires git-lfs)
   git lfs install
   git clone https://huggingface.co/prince-canuma/Kokoro-82M temp
   cp temp/kokoro-v1_0.safetensors KokoroVoice/Resources/
   rm -rf temp

   # Download voices
   git clone https://huggingface.co/hexgrad/Kokoro-82M temp2
   cp temp2/voices/*.pt KokoroVoice/Resources/voices/
   rm -rf temp2
   ```

2. **Add to Xcode**:
   - Drag `Resources` folder into Xcode
   - Select "Copy items if needed"
   - Add to both targets

### Apple Developer Setup

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
