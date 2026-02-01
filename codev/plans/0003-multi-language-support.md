# Plan 0003: Multi-Language Support (Romance Languages)

## Overview

This plan adds Spanish, Italian, and Portuguese voice support to KokoroVoice using rule-based G2P (no GPL dependencies).

**Spec:** [codev/specs/0003-multi-language-support.md](../specs/0003-multi-language-support.md)

**Scope:**
- 8 new voices: Spanish (3), Italian (2), Portuguese (3)
- 10 new English voices (completing the set)
- Rule-based G2P for Romance languages
- **Total: 36 voices** (28 English + 8 Romance)

## Phase 1: Rule-Based Romance G2P

**Goal:** Implement pure Swift G2P for Spanish, Italian, and Portuguese

### Tasks

1.1. **Create RomanceG2PProcessor**
```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/RomanceG2PProcessor.swift
final class RomanceG2PProcessor: G2PProcessor {
    private var currentLanguage: Language?

    func setLanguage(_ language: Language) throws {
        guard [.spanish, .italian, .brazilianPortuguese].contains(language) else {
            throw G2PProcessorError.unsupportedLanguage(language.rawValue)
        }
        currentLanguage = language
    }

    func process(input: String) throws -> String {
        guard let language = currentLanguage else {
            throw G2PProcessorError.processorNotInitialized
        }

        switch language {
        case .spanish:
            return try processSpanish(input)
        case .italian:
            return try processItalian(input)
        case .brazilianPortuguese:
            return try processPortuguese(input)
        default:
            throw G2PProcessorError.unsupportedLanguage(language.rawValue)
        }
    }
}
```

1.2. **Implement Spanish G2P rules**

Spanish has nearly 1:1 grapheme-to-phoneme mapping:

```swift
private func processSpanish(_ text: String) throws -> String {
    var phonemes: [String] = []
    let chars = Array(text.lowercased())
    var i = 0

    while i < chars.count {
        let char = chars[i]
        let next = i + 1 < chars.count ? chars[i + 1] : nil

        switch char {
        // Vowels
        case "a": phonemes.append("a"); i += 1
        case "e": phonemes.append("e"); i += 1
        case "i": phonemes.append("i"); i += 1
        case "o": phonemes.append("o"); i += 1
        case "u": phonemes.append("u"); i += 1

        // Special consonants
        case "c":
            if next == "h" {
                phonemes.append("tʃ"); i += 2  // ch → tʃ
            } else if next == "e" || next == "i" {
                phonemes.append("θ"); i += 1   // ce, ci → θ (Spain) or s (Latin America)
            } else {
                phonemes.append("k"); i += 1
            }
        case "g":
            if next == "e" || next == "i" {
                phonemes.append("x"); i += 1   // ge, gi → x
            } else if next == "u" {
                phonemes.append("g"); i += 2   // gu → g
            } else {
                phonemes.append("g"); i += 1
            }
        case "j": phonemes.append("x"); i += 1
        case "ñ": phonemes.append("ɲ"); i += 1
        case "ll": phonemes.append("ʎ"); i += 2
        case "rr": phonemes.append("r"); i += 2  // Trilled r
        case "r": phonemes.append("ɾ"); i += 1   // Flapped r
        case "v", "b": phonemes.append("b"); i += 1
        case "z": phonemes.append("θ"); i += 1

        // Standard consonants
        case "d": phonemes.append("d"); i += 1
        case "f": phonemes.append("f"); i += 1
        case "k": phonemes.append("k"); i += 1
        case "l": phonemes.append("l"); i += 1
        case "m": phonemes.append("m"); i += 1
        case "n": phonemes.append("n"); i += 1
        case "p": phonemes.append("p"); i += 1
        case "s": phonemes.append("s"); i += 1
        case "t": phonemes.append("t"); i += 1
        case "x": phonemes.append("ks"); i += 1
        case "y": phonemes.append("ʝ"); i += 1

        // Silent letters
        case "h": i += 1  // Silent

        // Spaces and punctuation
        case " ": phonemes.append(" "); i += 1
        default: i += 1
        }
    }

    return phonemes.joined()
}
```

1.3. **Implement Italian G2P rules**

Italian is very regular (similar to Spanish):

```swift
private func processItalian(_ text: String) throws -> String {
    // Similar structure to Spanish
    // Key differences:
    // - c before e/i → tʃ (not θ)
    // - g before e/i → dʒ
    // - gli → ʎ
    // - gn → ɲ
    // - sc before e/i → ʃ
}
```

1.4. **Implement Portuguese G2P rules**

Portuguese is mostly regular with some nasal vowel rules:

```swift
private func processPortuguese(_ text: String) throws -> String {
    // Key features:
    // - Nasal vowels: ã, õ, etc.
    // - lh → ʎ
    // - nh → ɲ
    // - x has multiple pronunciations based on context
}
```

1.5. **Create PhonemeNormalizer**

Validate output against Kokoro's vocabulary:

```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/PhonemeNormalizer.swift
struct PhonemeNormalizer {
    /// Kokoro's phoneme vocabulary (subset relevant for Romance languages)
    static let kokoroVocabulary: Set<String> = [
        "a", "b", "d", "e", "f", "g", "i", "k", "l", "m", "n", "o", "p",
        "r", "s", "t", "u", "v", "w", "x", "z",
        "ɾ", "ʎ", "ɲ", "θ", "ʝ", "tʃ", "dʒ", "ʃ", "ks",
        // ... complete set
    ]

    static func normalize(_ phonemes: String) throws -> String {
        // Validate each phoneme against vocabulary
        // Map common variants
        // Report unmappable phonemes
    }
}
```

### Tests
- Spanish "Hola mundo" produces valid phonemes
- Italian "Ciao mondo" produces valid phonemes
- Portuguese "Olá mundo" produces valid phonemes
- All phonemes are in Kokoro vocabulary

### Acceptance Criteria
- [ ] RomanceG2PProcessor builds without errors
- [ ] Spanish G2P produces correct IPA for test sentences
- [ ] Italian G2P produces correct IPA for test sentences
- [ ] Portuguese G2P produces correct IPA for test sentences
- [ ] PhonemeNormalizer validates all output

---

## Phase 2: Add Voice Definitions and Embeddings

**Goal:** Add all 18 new voice definitions and download embeddings

### Tasks

2.1. **Update Language enum**
```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/Language.swift
public enum Language: String {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case spanish = "es-ES"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"
}
```

2.2. **Add SupportedLanguage enum to Shared**
```swift
// Shared/Constants.swift
public enum SupportedLanguage: String, CaseIterable {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case spanish = "es-ES"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"

    var defaultVoiceId: String {
        switch self {
        case .americanEnglish: return "af_heart"
        case .britishEnglish: return "bf_emma"
        case .spanish: return "ef_dora"
        case .italian: return "if_sara"
        case .brazilianPortuguese: return "pf_dora"
        }
    }
}
```

2.3. **Add missing English voices (10 total)**
```swift
// Add to Constants.availableVoices:
// en-US male (6 new)
VoiceDefinition(id: "am_eric", name: "Eric", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_fenrir", name: "Fenrir", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_liam", name: "Liam", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_onyx", name: "Onyx", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_puck", name: "Puck", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_santa", name: "Santa", language: "en-US", gender: .male, quality: .b),

// en-GB (4 new)
VoiceDefinition(id: "bf_isabella", name: "Isabella", language: "en-GB", gender: .female, quality: .b),
VoiceDefinition(id: "bf_lily", name: "Lily", language: "en-GB", gender: .female, quality: .b),
VoiceDefinition(id: "bm_fable", name: "Fable", language: "en-GB", gender: .male, quality: .b),
VoiceDefinition(id: "bm_lewis", name: "Lewis", language: "en-GB", gender: .male, quality: .b),
```

2.4. **Add Romance language voices (8 total)**
```swift
// Spanish (3)
VoiceDefinition(id: "ef_dora", name: "Dora", language: "es-ES", gender: .female, quality: .b),
VoiceDefinition(id: "em_alex", name: "Alex", language: "es-ES", gender: .male, quality: .b),
VoiceDefinition(id: "em_santa", name: "Santa", language: "es-ES", gender: .male, quality: .b),

// Italian (2)
VoiceDefinition(id: "if_sara", name: "Sara", language: "it-IT", gender: .female, quality: .b),
VoiceDefinition(id: "im_nicola", name: "Nicola", language: "it-IT", gender: .male, quality: .b),

// Brazilian Portuguese (3)
VoiceDefinition(id: "pf_dora", name: "Dora", language: "pt-BR", gender: .female, quality: .b),
VoiceDefinition(id: "pm_alex", name: "Alex", language: "pt-BR", gender: .male, quality: .b),
VoiceDefinition(id: "pm_santa", name: "Santa", language: "pt-BR", gender: .male, quality: .b),
```

2.5. **Download voice embeddings**
```bash
# Update scripts/download-models.sh
# Download 18 new .safetensors files from Hugging Face
```

2.6. **Update project.yml for resources**
```yaml
targets:
  KokoroVoiceShared:
    sources:
      - path: Shared
      - path: Resources/voices
        buildPhase: resources
```

### Tests
- All 36 voice definitions exist and are unique
- All 18 new .safetensors files are present
- Voice IDs match expected pattern

### Acceptance Criteria
- [ ] 18 new voice embedding files in Resources/voices/
- [ ] All voices defined in Constants.swift
- [ ] Files included in Shared framework bundle

---

## Phase 3: Update Engine and AudioUnit

**Goal:** Integrate Romance G2P and register voices with system

### Tasks

3.1. **Create CompositeG2PProcessor**
```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/CompositeG2PProcessor.swift
final class CompositeG2PProcessor: G2PProcessor {
    private var misakiProcessor: MisakiG2PProcessor?
    private var romanceProcessor: RomanceG2PProcessor?
    private var currentLanguage: Language?

    func setLanguage(_ language: Language) throws {
        currentLanguage = language
        switch language {
        case .americanEnglish, .britishEnglish:
            if misakiProcessor == nil { misakiProcessor = MisakiG2PProcessor() }
            try misakiProcessor?.setLanguage(language)
        case .spanish, .italian, .brazilianPortuguese:
            if romanceProcessor == nil { romanceProcessor = RomanceG2PProcessor() }
            try romanceProcessor?.setLanguage(language)
        }
    }

    func process(input: String) throws -> String {
        guard let language = currentLanguage else {
            throw G2PProcessorError.processorNotInitialized
        }
        switch language {
        case .americanEnglish, .britishEnglish:
            return try misakiProcessor?.process(input: input) ?? ""
        case .spanish, .italian, .brazilianPortuguese:
            return try romanceProcessor?.process(input: input) ?? ""
        }
    }
}
```

3.2. **Update KokoroEngine for composite G2P**
```swift
// Shared/KokoroEngine.swift
tts = try KokoroTTS(modelPath: modelFile, g2p: .composite)
```

3.3. **Update speechVoices property**
```swift
// KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift
public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
    let enabledVoiceIds = VoiceConfiguration.shared.enabledVoiceIds
    return Constants.availableVoices
        .filter { enabledVoiceIds.contains($0.id) }
        .map { voice in
            AVSpeechSynthesisProviderVoice(
                name: voice.name,
                identifier: Constants.voiceIdentifierPrefix + voice.id,
                primaryLanguages: [voice.language],
                supportedLanguages: [voice.language]
            )
        }
}
```

3.4. **Update synthesizeSpeechRequest for language routing**
```swift
override public func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
    let voiceId = request.voice.identifier.replacingOccurrences(
        of: Constants.voiceIdentifierPrefix, with: ""
    )

    guard let voiceDef = Constants.voiceDefinition(forId: voiceId) else {
        // Unknown voice - fail gracefully
        return
    }

    let language = voiceDef.language
    // Pass language to synthesis
}
```

### Tests
- CompositeG2PProcessor routes English to Misaki
- CompositeG2PProcessor routes Spanish/Italian/Portuguese to RomanceG2P
- Voices appear in System Preferences
- VoiceOver can select Romance voices

### Acceptance Criteria
- [ ] English synthesis still works (Misaki)
- [ ] Spanish synthesis works
- [ ] Italian synthesis works
- [ ] Portuguese synthesis works
- [ ] All voices appear in System Preferences

---

## Phase 4: Testing and Validation

**Goal:** Comprehensive testing and quality validation

### Tasks

4.1. **Unit tests**
```swift
final class RomanceG2PTests: XCTestCase {
    func testSpanishPhonemes() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let result = try processor.process(input: "Hola mundo")
        XCTAssertFalse(result.isEmpty)
        // Validate against expected phonemes
    }

    func testItalianPhonemes() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.italian)

        let result = try processor.process(input: "Ciao mondo")
        XCTAssertFalse(result.isEmpty)
    }

    func testPortuguesePhonemes() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.brazilianPortuguese)

        let result = try processor.process(input: "Olá mundo")
        XCTAssertFalse(result.isEmpty)
    }
}
```

4.2. **Integration tests**
```swift
func testSynthesizeRomanceLanguages() async throws {
    let engine = KokoroEngine.shared

    let testPhrases: [(String, String, String)] = [
        ("es-ES", "ef_dora", "Hola, ¿cómo estás?"),
        ("it-IT", "if_sara", "Ciao, come stai?"),
        ("pt-BR", "pf_dora", "Olá, como vai?"),
    ]

    for (language, voiceId, text) in testPhrases {
        let audio = try await engine.synthesize(text: text, voiceId: voiceId, language: language)
        XCTAssertGreaterThan(audio.count, 1000, "Audio too short for \(language)")
    }
}
```

4.3. **Manual testing checklist**
- [ ] Spanish voices appear in System Preferences → Spoken Content
- [ ] Italian voices appear in System Preferences → Spoken Content
- [ ] Portuguese voices appear in System Preferences → Spoken Content
- [ ] VoiceOver works with Spanish voice selected
- [ ] VoiceOver works with Italian voice selected
- [ ] VoiceOver works with Portuguese voice selected
- [ ] Audio quality is acceptable for each language

### Acceptance Criteria
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing checklist complete

---

## File Changes Summary

| File | Action | Lines |
|------|--------|-------|
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/RomanceG2PProcessor.swift` | Create | ~300 |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/PhonemeNormalizer.swift` | Create | ~50 |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/CompositeG2PProcessor.swift` | Create | ~50 |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/Language.swift` | Modify | +3 |
| `Shared/Constants.swift` | Modify | +50 |
| `Shared/KokoroEngine.swift` | Modify | +10 |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Modify | +5 |
| `Resources/voices/*.safetensors` | Create | 18 files |
| `project.yml` | Modify | +3 |
| `Tests/RomanceG2PTests.swift` | Create | ~100 |

**Total:** ~500 new lines of code, 18 new resource files

---

## Risk Mitigation

| Risk | Priority | Mitigation |
|------|----------|------------|
| Phoneme format mismatch | High | Compare output against espeak-ng reference; build normalization layer |
| Rule-based G2P quality | Medium | Start with Spanish (most regular); iterate based on listening tests |
| Voice embedding format | Low | Verify .safetensors files match existing English voices |

---

## Success Criteria

1. **All 36 voices work** - English + Romance synthesis functions correctly
2. **No GPL dependencies** - Pure Swift rule-based G2P
3. **Quality acceptable** - Audio sounds natural for all three Romance languages
4. **System integration** - Voices appear in System Preferences, VoiceOver works
