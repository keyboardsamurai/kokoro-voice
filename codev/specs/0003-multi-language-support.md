# Spec 0003: Multi-Language Support

## Status
**conceived** - Awaiting human approval

## Problem Statement

KokoroVoice currently only supports English (US/GB) voices despite the Kokoro-82M model supporting 9 languages with 62 voices.

**Current state:**
- 18 voices defined in `Constants.swift` (en-US and en-GB only)
- Model files for other languages exist but are unused
- ~80% of potential users who need other languages cannot use KokoroVoice

**Impact:** This is the #1 blocker to broader adoption.

## Goals

1. **Support all 9 Kokoro languages** - Japanese, Mandarin Chinese, Spanish, French, Hindi, Italian, Brazilian Portuguese, plus existing English
2. **62 voices total** - All voices from Kokoro-82M voice embeddings
3. **Automatic language detection** - System routes requests to appropriate voices
4. **Graceful degradation** - If voice embedding missing, fall back to default
5. **No model changes** - Voice embeddings are separate `.pt` files; base model unchanged

## Non-Goals

- Adding new languages beyond what Kokoro-82M supports
- Training new voice embeddings
- UI translation/localization (separate spec if needed)
- Mixing languages within a single utterance

## Available Voices (from Kokoro-82M)

| Language | Code | Female | Male | Total | Notes |
|----------|------|--------|------|-------|-------|
| American English | en-US | 11 | 9 | 20 | Best quality voices |
| British English | en-GB | 4 | 4 | 8 | Good quality |
| Japanese | ja-JP | 4 | 1 | 5 | B-C grade |
| Mandarin Chinese | zh-CN | 4 | 4 | 8 | C-D grade |
| Spanish | es-ES | 1 | 2 | 3 | Limited metadata |
| French | fr-FR | 1 | 0 | 1 | Single voice |
| Hindi | hi-IN | 2 | 2 | 4 | B-C grade |
| Italian | it-IT | 1 | 1 | 2 | B-C grade |
| Brazilian Portuguese | pt-BR | 1 | 2 | 3 | Limited metadata |
| **Total** | | **29** | **25** | **54** | |

## Technical Design

### Voice Definition Updates

Expand `Constants.VoiceDefinition` to include all languages:

```swift
public static let availableVoices: [VoiceDefinition] = [
    // === American English (20 voices) ===
    VoiceDefinition(id: "af_heart", name: "Kokoro Heart", language: "en-US", gender: .female, quality: .a),
    VoiceDefinition(id: "af_bella", name: "Kokoro Bella", language: "en-US", gender: .female, quality: .a),
    // ... (existing + new US voices)

    // === British English (8 voices) ===
    VoiceDefinition(id: "bf_emma", name: "Kokoro Emma", language: "en-GB", gender: .female, quality: .b),
    // ...

    // === Japanese (5 voices) ===
    VoiceDefinition(id: "jf_alpha", name: "Kokoro Alpha", language: "ja-JP", gender: .female, quality: .b),
    VoiceDefinition(id: "jf_gongitsune", name: "Kokoro Gongitsune", language: "ja-JP", gender: .female, quality: .b),
    VoiceDefinition(id: "jf_nezumi", name: "Kokoro Nezumi", language: "ja-JP", gender: .female, quality: .b),
    VoiceDefinition(id: "jf_tebukuro", name: "Kokoro Tebukuro", language: "ja-JP", gender: .female, quality: .b),
    VoiceDefinition(id: "jm_kumo", name: "Kokoro Kumo", language: "ja-JP", gender: .male, quality: .b),

    // === Mandarin Chinese (8 voices) ===
    VoiceDefinition(id: "zf_xiaobei", name: "Kokoro Xiaobei", language: "zh-CN", gender: .female, quality: .b),
    VoiceDefinition(id: "zf_xiaoni", name: "Kokoro Xiaoni", language: "zh-CN", gender: .female, quality: .b),
    VoiceDefinition(id: "zf_xiaoxiao", name: "Kokoro Xiaoxiao", language: "zh-CN", gender: .female, quality: .b),
    VoiceDefinition(id: "zf_xiaoyi", name: "Kokoro Xiaoyi", language: "zh-CN", gender: .female, quality: .b),
    VoiceDefinition(id: "zm_yunjian", name: "Kokoro Yunjian", language: "zh-CN", gender: .male, quality: .b),
    VoiceDefinition(id: "zm_yunxi", name: "Kokoro Yunxi", language: "zh-CN", gender: .male, quality: .b),
    VoiceDefinition(id: "zm_yunxia", name: "Kokoro Yunxia", language: "zh-CN", gender: .male, quality: .b),
    VoiceDefinition(id: "zm_yunyang", name: "Kokoro Yunyang", language: "zh-CN", gender: .male, quality: .b),

    // === Spanish (3 voices) ===
    VoiceDefinition(id: "ef_dora", name: "Kokoro Dora", language: "es-ES", gender: .female, quality: .b),
    VoiceDefinition(id: "em_alex", name: "Kokoro Alex", language: "es-ES", gender: .male, quality: .b),
    VoiceDefinition(id: "em_santa", name: "Kokoro Santa", language: "es-ES", gender: .male, quality: .b),

    // === French (1 voice) ===
    VoiceDefinition(id: "ff_siwis", name: "Kokoro Siwis", language: "fr-FR", gender: .female, quality: .b),

    // === Hindi (4 voices) ===
    VoiceDefinition(id: "hf_alpha", name: "Kokoro Alpha", language: "hi-IN", gender: .female, quality: .b),
    VoiceDefinition(id: "hf_beta", name: "Kokoro Beta", language: "hi-IN", gender: .female, quality: .b),
    VoiceDefinition(id: "hm_omega", name: "Kokoro Omega", language: "hi-IN", gender: .male, quality: .b),
    VoiceDefinition(id: "hm_psi", name: "Kokoro Psi", language: "hi-IN", gender: .male, quality: .b),

    // === Italian (2 voices) ===
    VoiceDefinition(id: "if_sara", name: "Kokoro Sara", language: "it-IT", gender: .female, quality: .b),
    VoiceDefinition(id: "im_nicola", name: "Kokoro Nicola", language: "it-IT", gender: .male, quality: .b),

    // === Brazilian Portuguese (3 voices) ===
    VoiceDefinition(id: "pf_dora", name: "Kokoro Dora", language: "pt-BR", gender: .female, quality: .b),
    VoiceDefinition(id: "pm_alex", name: "Kokoro Alex", language: "pt-BR", gender: .male, quality: .b),
    VoiceDefinition(id: "pm_santa", name: "Kokoro Santa", language: "pt-BR", gender: .male, quality: .b),
]
```

### Language Code Mapping

Add BCP-47 language code support for system integration:

```swift
/// Supported languages with their BCP-47 codes
public enum SupportedLanguage: String, CaseIterable {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case japanese = "ja-JP"
    case mandarinChinese = "zh-CN"
    case spanish = "es-ES"
    case french = "fr-FR"
    case hindi = "hi-IN"
    case italian = "it-IT"
    case portugueseBrazilian = "pt-BR"

    /// Voices available for this language
    var voices: [VoiceDefinition] {
        Constants.availableVoices.filter { $0.language == self.rawValue }
    }

    /// Default voice for this language
    var defaultVoice: VoiceDefinition? {
        voices.first { $0.quality == .a } ?? voices.first
    }
}
```

### Voice Embedding Files

Voice embeddings are stored as `.pt` (PyTorch) files, one per voice:

```
Resources/voices/
├── af_heart.pt      # American English female
├── af_bella.pt
├── jf_alpha.pt      # Japanese female
├── jf_gongitsune.pt
├── zf_xiaobei.pt    # Mandarin female
└── ...
```

**File size:** ~100-200KB per voice embedding
**Total additional size:** ~5-10MB for all 44 new voices

### KokoroEngine Updates

Update voice loading in `KokoroEngine.swift`:

```swift
func loadVoiceEmbedding(voiceId: String) async throws -> MLXArray {
    let voicePath = Bundle.main.path(forResource: voiceId, ofType: "pt", inDirectory: "voices")
    guard let path = voicePath else {
        // Fallback to default voice
        print("KokoroEngine: Voice \(voiceId) not found, using default")
        return try await loadVoiceEmbedding(voiceId: "af_heart")
    }
    return try await loadPyTorchTensor(from: path)
}
```

### AudioUnit Voice Registration

Update `KokoroSynthesisAudioUnit` to register all voices with the system:

```swift
public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
    return Constants.availableVoices.map { voice in
        AVSpeechSynthesisProviderVoice(
            name: voice.name,
            identifier: voice.id,
            primaryLanguages: [voice.language],
            supportedLanguages: [voice.language]
        )
    }
}
```

### System Voice Selection

VoiceOver/Spoken Content selects voices based on system language. For each enabled voice, the system sees:
- Voice name ("Kokoro Heart")
- Voice identifier ("af_heart")
- Primary language ("en-US", "ja-JP", etc.)

Users can enable/disable voices in KokoroVoice settings. Only enabled voices appear in System Preferences.

## Implementation Phases

### Phase 1: Add Voice Definitions
- Update `Constants.swift` with all 54 voices
- Add `SupportedLanguage` enum
- Update `defaultEnabledVoiceIds` to include one voice per language

### Phase 2: Download Voice Embeddings
- Download all `.pt` files from Hugging Face
- Add to `Resources/voices/` directory
- Update Xcode project to include new resources

### Phase 3: Update Engine
- Modify `KokoroEngine.swift` to load any voice embedding
- Add fallback for missing embeddings
- Test synthesis in all languages

### Phase 4: Update AudioUnit
- Register all voices with system
- Verify voices appear in System Preferences
- Test VoiceOver with different system languages

### Phase 5: Testing
- Test each language with native text
- Verify fallback behavior
- Test voice switching

## Success Criteria

1. **All 54 voices work** - Each voice synthesizes appropriate language correctly
2. **System integration** - All voices appear in System Preferences → Accessibility → Spoken Content
3. **VoiceOver compatible** - Users can select non-English voices in VoiceOver settings
4. **Fallback works** - Missing embedding falls back to default without crash
5. **App size reasonable** - Total app size increase < 15MB

## Testing Plan

### Unit Tests
- Voice definition lookup by ID
- Language code mapping
- Fallback behavior for missing embeddings

### Integration Tests
- Synthesize text in each language
- Voice switching mid-session
- System voice registration

### Manual Testing
- Enable Japanese system language, verify Japanese voices appear
- VoiceOver in Chinese, verify Chinese voices work
- Live Speech in Spanish, verify Spanish voices work

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Voice quality varies by language | High | Medium | Document quality grades in UI; prioritize A/B grade voices |
| Missing embedding files | Low | High | Fallback to default; log warning |
| App size too large | Medium | Low | Consider on-demand download for less common languages |
| Language detection issues | Medium | Medium | Let system handle; don't second-guess |

## Dependencies

- Voice embedding files from Hugging Face (`hexgrad/Kokoro-82M`)
- No model file changes required
- KokoroSwift library already supports multi-language

## Files to Modify

| File | Changes |
|------|---------|
| `Shared/Constants.swift` | Add 36 new voice definitions, add `SupportedLanguage` enum |
| `Shared/KokoroEngine.swift` | Update voice loading with fallback |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Verify voice registration |
| `Resources/voices/` | Add 36 new `.pt` files |
| `project.yml` | Include new voice files in bundle |

## Estimated Scope

- **Complexity:** Medium
- **New code:** ~100 lines
- **Modified code:** ~50 lines
- **New resources:** ~5-10MB (voice embeddings)
- **Testing:** Significant (9 languages × multiple voices)

## Future Enhancements

- UI localization (translate settings UI)
- Voice quality indicators in UI
- On-demand voice downloading
- Language auto-detection from text (not relying on system)
