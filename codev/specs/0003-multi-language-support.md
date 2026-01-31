# Spec 0003: Multi-Language Support (Romance Languages)

## Status
**planned** - Approved for implementation

## Scope Reduction Notice

**Original scope:** 9 languages, 54 voices, eSpeakNG G2P (GPL-3.0)

**Reduced scope:** 5 languages (English + 3 Romance), 36 voices, rule-based G2P (no GPL)

**Reason:** eSpeakNG's GPL-3.0 license is unacceptable. Romance languages (Spanish, Italian, Portuguese) have regular orthography enabling pure Swift rule-based G2P. Japanese, Chinese, French, and Hindi are deferred to a future spec.

## Problem Statement

KokoroVoice currently only supports English (US/GB) voices despite the Kokoro-82M model supporting multiple languages.

**Current state:**
- 18 voices defined in `Constants.swift` (en-US and en-GB only, missing 10 English voices)
- G2P (Grapheme-to-Phoneme) uses MisakiSwift which only supports English
- Model files for other languages exist but are unused

**Impact:** Users who need Spanish, Italian, or Portuguese cannot use KokoroVoice.

## Goals

1. **Support 3 Romance languages** - Spanish, Italian, Brazilian Portuguese (plus existing English)
2. **36 voices total** - 28 English + 8 Romance (completing English set + adding Romance)
3. **Rule-based G2P** - Pure Swift implementation for Romance languages (no GPL dependencies)
4. **Graceful degradation** - If voice embedding missing, fall back to language default then fail safely
5. **System voice selection** - Let macOS handle language routing via `AVSpeechSynthesisProviderVoice`
6. **No model changes** - Voice embeddings are separate `.safetensors` files; base model unchanged

## Non-Goals

- Japanese, Chinese, French, Hindi support (deferred - requires complex G2P)
- Adding new languages beyond what Kokoro-82M supports
- Training new voice embeddings
- UI translation/localization (separate spec if needed)
- Mixing languages within a single utterance
- Auto-detecting language from text (defer to system language settings)
- On-demand voice downloading (bundle all voices)

## Available Voices (In Scope)

**Source:** [hexgrad/Kokoro-82M VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)

| Language | Code | Female | Male | Total | Default Voice | Notes |
|----------|------|--------|------|-------|---------------|-------|
| American English | en-US | 11 | 9 | 20 | af_heart | Best quality (A grade) |
| British English | en-GB | 4 | 4 | 8 | bf_emma | Good quality (A-B grade) |
| Spanish | es-ES | 1 | 2 | 3 | ef_dora | Rule-based G2P |
| Italian | it-IT | 1 | 1 | 2 | if_sara | Rule-based G2P |
| Brazilian Portuguese | pt-BR | 1 | 2 | 3 | pf_dora | Rule-based G2P |
| **Total (In Scope)** | | **18** | **18** | **36** | | |

### Deferred Languages (Future Spec)

| Language | Code | Voices | Reason for Deferral |
|----------|------|--------|---------------------|
| Japanese | ja-JP | 5 | Requires MeCab (50MB dictionary) |
| Mandarin Chinese | zh-CN | 8 | Complex tones, heteronyms |
| French | fr-FR | 1 | Irregular orthography (liaisons) |
| Hindi | hi-IN | 4 | Devanagari script complexity |

### Voice IDs (In Scope)

```
# American English (20)
af_heart, af_alloy, af_aoede, af_bella, af_jessica, af_kore, af_nicole, af_nova, af_river, af_sarah, af_sky
am_adam, am_echo, am_eric, am_fenrir, am_liam, am_michael, am_onyx, am_puck, am_santa

# British English (8)
bf_alice, bf_emma, bf_isabella, bf_lily
bm_daniel, bm_fable, bm_george, bm_lewis

# Spanish (3)
ef_dora
em_alex, em_santa

# Italian (2)
if_sara
im_nicola

# Brazilian Portuguese (3)
pf_dora
pm_alex, pm_santa
```

### Voice Additions Summary

| Category | Current | Target | To Add |
|----------|---------|--------|--------|
| en-US voices | 14 | 20 | +6 (am_eric, am_fenrir, am_liam, am_onyx, am_puck, am_santa) |
| en-GB voices | 4 | 8 | +4 (bf_isabella, bf_lily, bm_fable, bm_lewis) |
| Romance languages | 0 | 8 | +8 (Spanish 3, Italian 2, Portuguese 3) |
| **Total** | **18** | **36** | **+18** |

## Technical Design

### Language Source at Runtime

**Where does the language string come from?**

The synthesis request flow provides language via the voice identifier:

```
macOS System → AVSpeechSynthesisProviderRequest → voice.identifier → KokoroVoiceExtension
```

```swift
// KokoroSynthesisAudioUnit.swift - extracting language from synthesis request
override public func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
    // Voice identifier format: "com.kokorovoice.{voiceId}"
    let voiceId = request.voice.identifier.replacingOccurrences(
        of: Constants.voiceIdentifierPrefix, with: ""
    )

    // Look up voice definition to get language
    guard let voiceDef = Constants.voiceDefinition(forId: voiceId) else {
        // Unknown voice - fail gracefully
        return
    }

    let language = voiceDef.language  // e.g., "es-ES"
    // Pass language to KokoroEngine for G2P selection
}
```

**Per-utterance voice selection:** Users select specific voices in System Preferences → Accessibility → Spoken Content. The system sends the selected voice identifier with each synthesis request. Users can have multiple Spanish voices enabled and switch between them.

### G2P (Grapheme-to-Phoneme) Engine

**Approach:** Pure Swift rule-based G2P for Romance languages. No GPL dependencies.

**Why rule-based works for Romance languages:**
- Spanish: Nearly 1:1 grapheme-to-phoneme mapping
- Italian: Very regular orthography
- Portuguese: Mostly regular with some rules for nasal vowels

**No external dependencies required.** The rule-based G2P is implemented entirely in Swift.

### Hybrid G2P Architecture

Since `KokoroTTS.swift` is initialized with a single fixed G2P engine, we need a **CompositeG2PProcessor** that routes to Misaki (English) or RomanceG2P (Spanish/Italian/Portuguese).

**Thread-safety:** The processor is created per-synthesis request (not shared), so mutable state is safe. Each `synthesizeSpeechRequest` call creates its own processing context.

```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/CompositeG2PProcessor.swift
final class CompositeG2PProcessor: G2PProcessor {
    // Per-request instance - no shared mutable state concerns
    private var misakiProcessor: MisakiG2PProcessor?
    private var romanceProcessor: RomanceG2PProcessor?
    private var currentLanguage: Language?

    func setLanguage(_ language: Language) throws {
        currentLanguage = language

        switch language {
        case .americanEnglish, .britishEnglish:
            if misakiProcessor == nil {
                misakiProcessor = MisakiG2PProcessor()
            }
            try misakiProcessor?.setLanguage(language)
        case .spanish, .italian, .brazilianPortuguese:
            if romanceProcessor == nil {
                romanceProcessor = RomanceG2PProcessor()
            }
            try romanceProcessor?.setLanguage(language)
        default:
            throw G2PProcessorError.unsupportedLanguage(language.rawValue)
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
        default:
            throw G2PProcessorError.unsupportedLanguage(language.rawValue)
        }
    }
}
```

### RomanceG2PProcessor

Rule-based G2P for Spanish, Italian, and Portuguese:

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

        let normalizedText = input.lowercased()
        var phonemes: [String] = []

        // Process text character by character with context-aware rules
        // (Implementation details in plan)

        return phonemes.joined(separator: " ")
    }
}
```

### Phoneme Normalization

**Critical:** Kokoro was trained with espeak-ng IPA phonemes. The rule-based G2P must produce compatible output.

```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/PhonemeNormalizer.swift
struct PhonemeNormalizer {
    /// Kokoro's 178-phoneme vocabulary (from config.json)
    static let kokoroVocabulary: Set<String> = [
        "a", "b", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
        "r", "s", "t", "u", "v", "w", "x", "z", "ɑ", "ɔ", "ə", "ɛ", "ɪ", "ʊ", "ʌ",
        // ... full vocabulary
    ]

    /// Normalize IPA phonemes to Kokoro vocabulary
    static func normalize(_ phonemes: String) throws -> String {
        // Map common IPA variants to Kokoro-expected symbols
        // Validate against vocabulary
        // Report unmappable phonemes
    }
}
```

### Language Enum Alignment

The package-level `Language` enum must be updated to support the 5 languages in scope:

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

**Conversion:** `SupportedLanguage` (app layer) and `Language` (package layer) use identical BCP-47 raw values, enabling direct conversion:

```swift
let language = Language(rawValue: supportedLanguage.rawValue)
```

**Update G2PFactory:**
```swift
public enum G2P {
    case misaki      // English only
    case romance     // Spanish, Italian, Portuguese
    case composite   // NEW: Misaki for English, Romance for es/it/pt
}
```

**KokoroTTS initialization:**
```swift
// KokoroEngine.swift
tts = try KokoroTTS(modelPath: modelFile, g2p: .composite)
```

### Phoneme Format Compatibility

**Approach:** Build phoneme output that matches Kokoro's vocabulary (178 phonemes from espeak-ng training).

**Validation required:** Compare rule-based G2P output against espeak-ng for test sentences. Build normalization layer to map any differences.

**Reference:** The upstream `hexgrad/kokoro` Python implementation uses `espeak-phonemizer` for non-English languages. Our rule-based approach must produce equivalent IPA sequences.

### Voice Definition Updates

**Voice naming convention:** Include language code to avoid display name collisions.

```swift
public static let availableVoices: [VoiceDefinition] = [
    // === American English (20 voices) ===
    VoiceDefinition(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a),
    VoiceDefinition(id: "af_bella", name: "Bella", language: "en-US", gender: .female, quality: .a),
    // ... (all en-US voices)

    // === British English (8 voices) ===
    VoiceDefinition(id: "bf_emma", name: "Emma", language: "en-GB", gender: .female, quality: .b),
    // ... (all en-GB voices)

    // === Spanish (3 voices) ===
    VoiceDefinition(id: "ef_dora", name: "Dora", language: "es-ES", gender: .female, quality: .b),
    VoiceDefinition(id: "em_alex", name: "Alex", language: "es-ES", gender: .male, quality: .b),
    VoiceDefinition(id: "em_santa", name: "Santa", language: "es-ES", gender: .male, quality: .b),

    // === Italian (2 voices) ===
    VoiceDefinition(id: "if_sara", name: "Sara", language: "it-IT", gender: .female, quality: .b),
    VoiceDefinition(id: "im_nicola", name: "Nicola", language: "it-IT", gender: .male, quality: .b),

    // === Brazilian Portuguese (3 voices) ===
    VoiceDefinition(id: "pf_dora", name: "Dora", language: "pt-BR", gender: .female, quality: .b),
    VoiceDefinition(id: "pm_alex", name: "Alex", language: "pt-BR", gender: .male, quality: .b),
    VoiceDefinition(id: "pm_santa", name: "Santa", language: "pt-BR", gender: .male, quality: .b),
]
```

**Note:** Voice names are now short (e.g., "Heart" not "Kokoro Heart"). The system UI will display as "Heart (English - US)" based on the language tag.

### Language Code Mapping

Add BCP-47 language code support with matching rules for system integration:

```swift
/// Supported languages with their BCP-47 codes
public enum SupportedLanguage: String, CaseIterable {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case spanish = "es-ES"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"

    /// Explicit default voice ID for each language (not computed)
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

### Language Matching Rules

```swift
extension SupportedLanguage {
    /// Match BCP-47 language code to supported language
    /// Handles variants like es-MX → es-ES, pt-PT → pt-BR
    static func match(bcp47 code: String) -> SupportedLanguage? {
        // Exact match first
        if let exact = SupportedLanguage(rawValue: code) {
            return exact
        }

        // Base language fallback
        let base = code.split(separator: "-").first.map(String.init) ?? code
        switch base {
        case "en": return .americanEnglish  // en-AU, en-CA, etc.
        case "es": return .spanish          // es-MX, es-AR, etc.
        case "it": return .italian
        case "pt": return .brazilianPortuguese  // pt-PT → pt-BR
        default: return nil
        }
    }
}
```

### System Language Matching

| System Language | Maps To | Notes |
|-----------------|---------|-------|
| `en-US`, `en` | en-US | Default English |
| `en-GB`, `en-AU`, `en-CA`, etc. | en-GB | British voice for non-US English |
| `es-ES`, `es-MX`, `es-AR`, `es` | es-ES | All Spanish variants |
| `it-IT`, `it` | it-IT | Italian |
| `pt-BR`, `pt-PT`, `pt` | pt-BR | Portuguese (Brazilian voices) |

### Voice Embedding Files

Voice embeddings are stored as `.safetensors` files, one per voice:

```
Resources/voices/
├── af_heart.safetensors      # American English female (default fallback)
├── af_bella.safetensors
├── ef_dora.safetensors       # Spanish female
├── if_sara.safetensors       # Italian female
├── pf_dora.safetensors       # Brazilian Portuguese female
└── ...                       # 36 files total
```

**File size:** ~100-200KB per voice embedding
**Total additional size:** ~3-4MB for all 18 new voices

### Resource Bundle Architecture

**Voice embeddings go in the Shared framework bundle**, accessible from both host app and extension.

**Why not Extension bundle?**
- `KokoroEngine` lives in `KokoroVoiceShared` framework
- `Bundle(for: KokoroEngine.self)` returns the Shared framework bundle
- Extension can't depend on Shared (circular), so resources in Extension bundle are inaccessible to engine code

**Solution:** Include voice resources in `KokoroVoiceShared` framework:

**project.yml configuration:**
```yaml
targets:
  KokoroVoiceShared:
    sources:
      - path: Shared
      - path: Resources/voices  # Voice embeddings in Shared framework bundle
        buildPhase: resources
    type: framework
```

**Bundle access (works in both app and extension):**
```swift
// KokoroEngine is in Shared framework, so this finds Shared framework's bundle
let sharedBundle = Bundle(for: KokoroEngine.self)
let voicePath = sharedBundle.path(forResource: voiceId, ofType: "safetensors", inDirectory: "voices")
```

**Verification:** Both host app and extension link `KokoroVoiceShared.framework`, which contains the voice resources. `Bundle(for: KokoroEngine.self)` correctly resolves to the framework bundle in both contexts.

### Build-Time Validation

Add a build phase script to verify all voice embeddings exist (for both app and extension):

```bash
#!/bin/bash
# Xcode Build Phase: Validate Voice Embeddings
# Works for both Debug/Release and app/extension targets

VOICES_DIR="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Resources/voices"
EXPECTED_VOICES=(af_heart af_alloy af_aoede ... ) # All 54 voice IDs

if [ ! -d "${VOICES_DIR}" ]; then
    echo "error: voices directory not found at ${VOICES_DIR}"
    exit 1
fi

for voice in "${EXPECTED_VOICES[@]}"; do
    if [ ! -f "${VOICES_DIR}/${voice}.safetensors" ]; then
        echo "error: Missing voice embedding: ${voice}.safetensors"
        exit 1
    fi
done

echo "All 54 voice embeddings validated successfully"
```

**Unit test using correct bundle:**
```swift
func testAllVoiceEmbeddingsExist() {
    // Use bundle containing the test class, which has access to resources
    let bundle = Bundle(for: type(of: self))
    for voice in Constants.availableVoices {
        let path = bundle.path(forResource: voice.id, ofType: "safetensors", inDirectory: "voices")
        XCTAssertNotNil(path, "Missing voice embedding: \(voice.id).safetensors")
    }
}
```

### KokoroEngine Updates

Update voice loading in `KokoroEngine.swift` with safe fallback (no recursion):

```swift
enum VoiceLoadingError: Error {
    case voiceNotFound(String)
    case defaultVoiceNotFound
    case tensorLoadFailed(String, Error)
}

/// Load voice embedding with language-aware fallback (no recursion)
/// Uses Bundle(for:) to work correctly in AudioUnit extension context
func loadVoiceEmbedding(voiceId: String, language: String) async throws -> MLXArray {
    // CRITICAL: Use extension bundle, not Bundle.main (which is the host app in extension context)
    let bundle = Bundle(for: KokoroEngine.self)

    // Only allow known voice IDs (prevent path traversal)
    guard Constants.availableVoices.contains(where: { $0.id == voiceId }) else {
        throw VoiceLoadingError.voiceNotFound(voiceId)
    }

    // 1. Try requested voice
    if let path = bundle.path(forResource: voiceId, ofType: "safetensors", inDirectory: "voices") {
        return try await loadSafetensors(from: path)
    }

    // 2. Log warning and try language default
    print("KokoroEngine: Voice \(voiceId) not found, trying language default")

    if let lang = SupportedLanguage(rawValue: language) {
        let defaultId = lang.defaultVoiceId
        if defaultId != voiceId,
           let defaultPath = bundle.path(forResource: defaultId, ofType: "safetensors", inDirectory: "voices") {
            return try await loadSafetensors(from: defaultPath)
        }
    }

    // 3. Last resort: af_heart (must exist or fail hard)
    if voiceId != "af_heart",
       let fallbackPath = bundle.path(forResource: "af_heart", ofType: "safetensors", inDirectory: "voices") {
        print("KokoroEngine: Using af_heart as last resort fallback")
        return try await loadSafetensors(from: fallbackPath)
    }

    // 4. Hard failure - no recursion, no silent failure
    throw VoiceLoadingError.defaultVoiceNotFound
}
```

**Fallback chain:** Requested voice → Language default → af_heart → Hard error

**Security:** Voice IDs are validated against known set before file lookup, preventing path traversal attacks.

### AudioUnit Voice Registration

Update `KokoroSynthesisAudioUnit` to register all voices with the system:

```swift
public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
    let enabledVoiceIds = VoiceConfiguration.shared.enabledVoiceIds
    return Constants.availableVoices
        .filter { enabledVoiceIds.contains($0.id) }
        .map { voice in
            AVSpeechSynthesisProviderVoice(
                name: voice.name,  // Short name, e.g., "Heart"
                identifier: Constants.voiceIdentifierPrefix + voice.id,
                primaryLanguages: [voice.language],
                supportedLanguages: [voice.language]
            )
        }
}
```

### System Voice Selection

VoiceOver/Spoken Content selects voices based on system language. The system UI automatically appends language info:
- Voice appears as: "Heart (English - US)" in System Preferences
- Voice identifier: "com.kokorovoice.af_heart"
- Primary language: "en-US"

**User preferences:** Stored in App Group (`group.com.kokorovoice.shared`) via `VoiceConfiguration`. Only enabled voices appear in System Preferences.

**Default enabled voices (one per language):**
```swift
public static var defaultEnabledVoiceIds: [String] {
    SupportedLanguage.allCases.map { $0.defaultVoiceId }
    // ["af_heart", "bf_emma", "jf_alpha", "zf_xiaobei", "ef_dora",
    //  "ff_siwis", "hf_alpha", "if_sara", "pf_dora"]
}
```

### VoiceConfiguration Validation

Validate voice IDs loaded from App Group shared storage:

```swift
// VoiceConfiguration.swift
public var enabledVoiceIds: [String] {
    let stored = userDefaults.stringArray(forKey: Constants.voicesKey) ?? []
    let validIds = Set(Constants.availableVoices.map { $0.id })

    // Filter out unknown voice IDs (from old versions or corruption)
    let validated = stored.filter { validIds.contains($0) }

    // Return defaults if empty after validation
    return validated.isEmpty ? Constants.defaultEnabledVoiceIds : validated
}
```

### Licensing and Attribution

**Dependencies:**

| Component | License | Attribution Required |
|-----------|---------|---------------------|
| eSpeakNGSwift | GPL-3.0 | Yes (in app credits) |
| eSpeakNG | GPL-3.0 | Yes (in app credits) |
| Kokoro-82M voices | Apache-2.0 | Yes (in app credits) |
| MisakiSwift | MIT | No |

**GPL-3.0 Compliance Decision:**

eSpeakNG is licensed under GPL-3.0. For KokoroVoice (macOS app distributed outside App Store):

1. **Acceptable use:** GPL allows distribution of compiled binaries that link to GPL libraries
2. **Obligation:** Must provide complete corresponding source code upon request
3. **Implementation:** Include "Source Code" link in app Credits pointing to GitHub repo
4. **Alternative:** If GPL is problematic, investigate MFA (Mozilla Festival Agreement) or other phonemizers

**Action required:** Legal review before v1.0 release. For internal/beta testing, GPL usage is acceptable.

**Attribution text (required in app Credits):**
```
This app uses:
- Kokoro-82M voice model (Apache-2.0, hexgrad)
- eSpeakNG text-to-phoneme engine (GPL-3.0, espeak-ng project)
  Source code available at: https://github.com/[repo-url]
```

### Asset Integrity

**Voice embedding files are checked into git** (not downloaded at build time):

```
Resources/voices/
├── af_heart.safetensors    # Checked in, tracked by git
├── ...
└── pm_santa.safetensors    # 54 files total
```

**Verification:**
1. Files are downloaded once from Hugging Face (`hexgrad/Kokoro-82M`)
2. SHA256 checksums recorded in `Resources/voices/checksums.txt`
3. CI validates checksums before building release builds

```bash
# checksums.txt format
af_heart.safetensors:sha256:abc123...
af_alloy.safetensors:sha256:def456...
```

## Implementation Phases

### Phase 1: Enable eSpeakNG G2P
- Uncomment eSpeakNG dependency in `LocalPackages/kokoro-ios/Package.swift`
- Run `swift package resolve` to fetch the dependency
- Verify eSpeakNG builds successfully with the project

### Phase 2: Add Voice Definitions
- Update `Constants.swift` with all 54 voices
- Add `SupportedLanguage` enum with language matching
- Update `defaultEnabledVoiceIds` to include one voice per language
- Add build-time validation script

### Phase 3: Download Voice Embeddings
- Download all `.safetensors` files from Hugging Face (`hexgrad/Kokoro-82M`)
- Add to `Resources/voices/` directory (36 new files)
- Update `project.yml` to include new resources in bundle

### Phase 4: Update Engine
- Modify `KokoroEngine.swift` for language-aware G2P selection
- Add safe voice embedding loading with fallback chain
- Test synthesis in all 9 languages

### Phase 5: Update AudioUnit
- Update `speechVoices` property to register all enabled voices
- Verify voices appear in System Preferences → Accessibility → Spoken Content
- Test VoiceOver with different system languages

### Phase 6: Testing & Validation
- Unit tests for voice definitions and language matching
- Integration tests for each language synthesis
- Build-time validation for voice embedding files
- Manual testing with VoiceOver and Spoken Content

## Graceful Failure Definition

When synthesis fails, the system should receive appropriate feedback:

| Failure Scenario | Behavior | User Experience |
|------------------|----------|-----------------|
| Voice file missing | Fallback chain tries: language default → af_heart → hard error | User hears fallback voice, error logged |
| G2P fails for language | Throw error, do not attempt synthesis | VoiceOver announces error, logged |
| Empty/invalid text | Return empty audio buffer | Silent, no announcement |
| Unknown language tag | Synthesis skipped, error logged | VoiceOver announces error |
| eSpeakNG not available | English-only mode (Misaki works) | Non-English voices disabled |

**Error surfacing:** Errors are logged via `print()` and throw `KokoroEngineError`. The system (`AVSpeechSynthesisProviderAudioUnit`) catches errors and signals failure to macOS, which announces to VoiceOver users.

## Voice Display Names

**macOS behavior confirmed:** System Preferences → Spoken Content displays voices as "Name (Language)" when multiple voices share the same name. Example: "Alpha (Japanese)" vs "Alpha (Hindi)".

**Short names used:** Voice definitions use short names ("Heart", "Alpha", "Dora") to avoid redundancy. The system UI handles disambiguation.

## Success Criteria

1. **All 54 voices work** - Each voice synthesizes appropriate language correctly
2. **eSpeakNG integrated** - Non-English G2P works without errors
3. **System integration** - Enabled voices appear in System Preferences → Accessibility → Spoken Content
4. **VoiceOver compatible** - Users can select non-English voices in VoiceOver settings
5. **Fallback works** - Missing embedding falls back gracefully without crash or infinite loop
6. **Build validation** - Missing voice files cause build failure
7. **App size reasonable** - Total app size increase < 15MB
8. **Graceful errors** - Errors surface to VoiceOver, don't cause crashes

## Testing Plan

### Unit Tests
- Voice definition uniqueness (no duplicate IDs)
- Language code matching (exact, fallback, and script variants like `zh-Hans`)
- Default voice selection per language
- VoiceConfiguration validation (reject unknown IDs, handle migration)
- `SupportedLanguage.match()` for all BCP-47 variants

### Integration Tests (Host App Context)

**Approach:** Tests run in host app context using `KokoroEngine` directly (not through AudioUnit). This validates core synthesis without extension sandboxing complexity.

```swift
func testSynthesizeAllLanguages() async throws {
    let engine = KokoroEngine.shared
    let testPhrases: [(String, String)] = [
        ("en-US", "Hello world"),
        ("ja-JP", "こんにちは"),
        ("zh-CN", "你好世界"),
        // ... all 9 languages
    ]

    for (language, text) in testPhrases {
        let audio = try await engine.synthesize(text: text, voiceId: defaultVoice(for: language), language: language)
        XCTAssertFalse(audio.isEmpty, "No audio for \(language)")
        XCTAssertGreaterThan(audio.count, 1000, "Audio too short for \(language)")
    }
}
```

- G2P engine selection (Misaki for English, eSpeakNG for others)
- Voice embedding loading with fallback chain
- Concurrency: simultaneous synthesis in different languages

### Manual Testing
- Enable Japanese system language, verify Japanese voices appear in System Preferences
- VoiceOver in Chinese, verify Chinese voices work
- Live Speech in Spanish, verify Spanish voices work
- Test with mixed content (English words in Japanese text)
- Verify fallback: disable a voice file, confirm graceful degradation

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| eSpeakNG integration issues | Medium | High | Test early in Phase 1; have contingency to disable non-English if blocked |
| Voice quality varies by language | High | Medium | Document quality grades in UI; prioritize A/B grade voices |
| eSpeakNG C-library build issues | Medium | High | Test on clean Xcode install; document build requirements |
| Missing embedding files | Low | High | Build-time validation + runtime fallback chain |
| App size too large | Low | Low | ~5-10MB acceptable; on-demand download is future enhancement |

## Dependencies

- **eSpeakNGSwift** (github.com/mlalma/eSpeakNGSwift ^1.0.1) - Multi-language G2P
- Voice embedding files from Hugging Face (`hexgrad/Kokoro-82M`)
- No base model file changes required

## Files to Modify

| File | Changes |
|------|---------|
| `LocalPackages/kokoro-ios/Package.swift` | Uncomment eSpeakNG dependency |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/Language.swift` | Add 7 new language cases (ja-JP, zh-CN, etc.) |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/CompositeG2PProcessor.swift` | **NEW:** Create hybrid G2P processor |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/G2PFactory.swift` | Add `.composite` enum case |
| `Shared/Constants.swift` | Add 36 new voice definitions, add `SupportedLanguage` enum |
| `Shared/KokoroEngine.swift` | Use `.composite` G2P, language-aware voice loading, use `Bundle(for:)` |
| `Shared/VoiceConfiguration.swift` | Add validation for unknown voice IDs |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Update `speechVoices`, pass language to engine |
| `Resources/voices/` | Add 36 new `.safetensors` files |
| `Resources/voices/checksums.txt` | **NEW:** SHA256 checksums for integrity |
| `project.yml` | Include voices in extension bundle, add build validation script |
| `Tests/VoiceConfigurationTests/` | Add validation tests, language matching tests |
| `KokoroVoice/Credits.rtf` or similar | Add GPL attribution text |

## Estimated Scope

- **Complexity:** Medium-High (eSpeakNG integration adds risk)
- **New code:** ~200 lines
- **Modified code:** ~100 lines
- **New resources:** ~5-10MB (36 voice embeddings)
- **Testing:** Significant (9 languages × multiple voices)

## Implementation Notes

These details should be addressed during implementation:

### G2PProcessor Protocol
The `G2PProcessor.process()` method returns `(String, [MToken]?)`, not just `String`. The `CompositeG2PProcessor` must forward the full tuple from the underlying processor.

### eSpeakNG Thread Safety
The eSpeakNG C library may use global state. During implementation:
1. Test concurrent synthesis in different languages
2. If thread-safety issues arise, add a serial queue for eSpeakNG calls
3. Document findings in the code

### eSpeakNG Data Resources
The `eSpeakNGSwift` package includes `espeak-ng-data` dictionaries. Verify:
1. Resources are accessible from AudioUnit extension context
2. Bundle paths resolve correctly in sandbox
3. Add to extension bundle if needed via `project.yml`

### Bundle Anchor Consistency
Use `Bundle(for: KokoroEngine.self)` consistently in all code. Since voices are in the Shared framework bundle, this works correctly in both host app and extension contexts.

### Checksum Enforcement
Checksums are enforced at build-time only (not runtime). CI pipeline should:
1. Verify checksums before building release builds
2. Fail build if checksums don't match
3. Runtime trusts that build validation passed

### Language Enum Migration
The `Language` enum in `KokoroSwift` changes case names. Update all call sites during implementation. Consider adding deprecated aliases for backward compatibility if external code uses the enum.

### Deployment Target
macOS 15.0+ (Sequoia) is already required. `AVSpeechSynthesisProviderVoice` API is stable on this version.

## Future Enhancements

- UI localization (translate settings UI)
- Voice quality indicators in UI
- On-demand voice downloading (reduce initial app size)
- Language auto-detection from text (beyond system language)
- Mixed-language utterance support (code-switching)
