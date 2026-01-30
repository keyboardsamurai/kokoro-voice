# Installing KokoroVoice

KokoroVoice brings high-quality neural text-to-speech voices to your Mac. This guide covers installation for the unsigned (free) distribution.

## Requirements

- **macOS 15.0** (Sequoia) or later
- **Apple Silicon** (M1, M2, M3, or M4 Mac)
- **~500MB** free disk space

## Quick Install

### Option 1: Easy Install Script (Recommended)

1. Open the DMG file
2. Open **Terminal** (Applications > Utilities > Terminal)
3. Drag `install.sh` into the Terminal window
4. Press **Enter** and follow the prompts

The script will:
- Check your system requirements
- Download model files if needed (~326MB)
- Remove Gatekeeper restrictions
- Install to /Applications
- Register the speech extension

### Option 2: Manual Install

1. **Open the DMG** and drag KokoroVoice to Applications

2. **Bypass Gatekeeper** (required for unsigned apps):
   - Right-click KokoroVoice.app in Applications
   - Click "Open"
   - Click "Open" again in the security dialog

3. **If you get a security warning**:
   - Go to System Settings > Privacy & Security
   - Scroll down to find the KokoroVoice message
   - Click "Open Anyway"

4. **Download models** (if not included):
   ```bash
   cd /Applications/KokoroVoice.app/Contents/Resources
   /Volumes/KokoroVoice/download-models.sh
   ```

## First Launch

1. **Open KokoroVoice** from Applications
2. **Wait for models to load** (30-60 seconds on first launch)
3. The app will display available voices when ready

## Enable Voices in macOS

After installing, enable voices for system-wide use:

1. Open **System Settings**
2. Go to **Accessibility** > **Spoken Content**
3. Click the **System Voice** dropdown
4. Click **Manage Voices...**
5. Scroll to **English** voices
6. Check the **Kokoro** voices you want to enable
7. Click **OK**

## Test the Voices

### From Terminal

```bash
# List available voices
say -v '?' | grep Kokoro

# Test a voice
say -v 'Kokoro Heart (Female)' 'Hello! KokoroVoice is working perfectly.'
```

### From System Settings

1. Go to **Accessibility** > **Spoken Content**
2. Select a Kokoro voice as your System Voice
3. Check "Speak selected text when the key is pressed"
4. Select some text and press the keyboard shortcut

## Troubleshooting

### Voices don't appear in System Settings

1. **Restart the speech daemon**:
   ```bash
   sudo killall -9 speechsynthesisd
   ```

2. **Log out and log back in**

3. **Verify the extension is registered**:
   ```bash
   pluginkit -m | grep KokoroVoice
   ```

### "App is damaged" or "Can't be opened"

This means Gatekeeper is blocking the unsigned app:

```bash
# Remove quarantine attribute
xattr -cr /Applications/KokoroVoice.app
```

Then try opening the app again.

### Model loading is slow

First launch loads ~326MB of neural network weights. Subsequent launches are faster. If loading takes more than 2 minutes:

1. Check that model files exist:
   ```bash
   ls -la /Applications/KokoroVoice.app/Contents/Resources/
   ```

2. Re-download models if needed:
   ```bash
   /path/to/download-models.sh
   ```

### Audio quality issues

- Ensure you're on Apple Silicon (Intel Macs are not supported)
- Check that your audio output device is working
- Try a different voice

## Available Voices

KokoroVoice includes 18 high-quality voices:

**American English (Female)**
- Kokoro Alloy, Aoede, Bella, Heart, Jessica, Kore, Nicole, Nova, River, Sarah, Sky

**American English (Male)**
- Kokoro Adam, Echo, Michael

**British English (Female)**
- Kokoro Alice, Emma

**British English (Male)**
- Kokoro Daniel, George

## Uninstalling

1. Delete `/Applications/KokoroVoice.app`
2. Restart the speech daemon:
   ```bash
   sudo killall -9 speechsynthesisd
   ```

## Building from Source

If you prefer to build from source:

```bash
git clone https://github.com/keyboardsamurai/kokoro-voice
cd kokorovoice/KokoroVoice
make download-models
make release
make install
```

See the README for development setup instructions.

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/keyboardsamurai/kokoro-voice/issues)
- **Discussions**: [GitHub Discussions](https://github.com/keyboardsamurai/kokoro-voice/discussions)

## License

KokoroVoice uses the Kokoro TTS model. See LICENSE for details.
