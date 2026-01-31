# Plan 0003: Multi-Language Support

## Overview

This plan implements multi-language TTS support for KokoroVoice, adding 36 new voices across 7 non-English languages plus completing the English voice set.

**Spec:** [codev/specs/0003-multi-language-support.md](../specs/0003-multi-language-support.md)

**Key Changes:**
1. Enable eSpeakNG G2P for non-English languages
2. Add 36 new voice definitions and embeddings
3. Update engine for language-aware G2P selection
4. Register all voices with system

## Phase 0: GPL-3.0 Decision Gate

**Goal:** Explicit go/no-go decision on eSpeakNG licensing before any code lands

**Background:** eSpeakNG is GPL-3.0 licensed. Linking (static or dynamic) a GPL-3 library into a distributed macOS app imposes GPL obligations on the **entire combined work**.

### Decision Required

Before proceeding with Phase 1, the project owner must explicitly decide:

| Question | Decision | Implications |
|----------|----------|--------------|
| Is GPL-3.0 acceptable for this project? | **YES** or **NO** | Determines whether we proceed with eSpeakNG |
| Distribution channel? | Direct download / Mac App Store / Both | App Store may have additional restrictions |
| Source availability? | Public repo / Written offer / Both | Required by GPL-3.0 |

**If YES (GPL acceptable):**
- Proceed with eSpeakNG as planned
- Ensure source availability (public repo or written offer)
- Include full GPL-3.0 license text in app bundle
- Document in README that project is GPL-3.0 due to eSpeakNG dependency

**If NO (GPL not acceptable):**
- **Alternative 1:** Investigate MFA (Mozilla Festival Agreement) phonemizers
- **Alternative 2:** Use English-only mode (Misaki) and defer multi-language
- **Alternative 3:** Build/ship eSpeakNG as separate process (IPC) to isolate GPL scope
- Create follow-up spec for alternative phonemizer research

### Acceptance Criteria
- [ ] GPL decision documented in project README or DECISIONS.md
- [ ] If NO: alternative phonemizer approach identified before Phase 1

---

## Phase 1: Enable eSpeakNG G2P

**Goal:** Get eSpeakNG dependency building and working

**Prerequisite:** Phase 0 decision = YES (GPL acceptable)

### Tasks

1.1. **Uncomment eSpeakNG dependency**
```swift
// LocalPackages/kokoro-ios/Package.swift
.package(url: "https://github.com/mlalma/eSpeakNGSwift", from: "1.0.1"),

// In KokoroSwift target dependencies:
.product(name: "eSpeakNGLib", package: "eSpeakNGSwift"),
```

1.2. **Add Language enum cases**
```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/Language.swift
public enum Language: String, CaseIterable {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case japanese = "ja-JP"
    case mandarinChinese = "zh-CN"
    case spanish = "es-ES"
    case french = "fr-FR"
    case hindi = "hi-IN"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"
}
```

1.3. **Create CompositeG2PProcessor**
```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/CompositeG2PProcessor.swift
final class CompositeG2PProcessor: G2PProcessor {
    private var misakiProcessor: MisakiG2PProcessor?
    private var eSpeakProcessor: eSpeakNGG2PProcessor?
    private var currentLanguage: Language?

    // Serial queue for eSpeakNG calls - the C library uses global state
    // and is NOT thread-safe. All eSpeakNG operations MUST go through this queue.
    private static let eSpeakQueue = DispatchQueue(label: "com.kokorovoice.espeak-ng")

    func setLanguage(_ language: Language) throws {
        currentLanguage = language
        switch language {
        case .americanEnglish, .britishEnglish:
            if misakiProcessor == nil { misakiProcessor = MisakiG2PProcessor() }
            try misakiProcessor?.setLanguage(language)
        default:
            if eSpeakProcessor == nil { eSpeakProcessor = eSpeakNGG2PProcessor() }
            // Serialize eSpeakNG language setting
            try Self.eSpeakQueue.sync {
                try eSpeakProcessor?.setLanguage(language)
            }
        }
    }

    func process(input: String) throws -> (String, [MToken]?) {
        guard let language = currentLanguage else {
            throw G2PProcessorError.processorNotInitialized
        }
        switch language {
        case .americanEnglish, .britishEnglish:
            return try misakiProcessor?.process(input: input) ?? ("", nil)
        default:
            // Serialize all eSpeakNG processing
            return try Self.eSpeakQueue.sync {
                try eSpeakProcessor?.process(input: input) ?? ("", nil)
            }
        }
    }
}
```

1.4. **Update G2PFactory**
```swift
// LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/G2PFactory.swift
public enum G2P {
    case misaki
    case eSpeakNG
    case composite  // NEW
}

// In createG2PProcessor:
case .composite:
    return CompositeG2PProcessor()
```

1.5. **Verify eSpeakNG builds**
```bash
cd LocalPackages/kokoro-ios
swift build
```

1.6. **Early spike: End-to-end Japanese synthesis**

Before scaling to 54 voices, verify a single non-English voice works:
```bash
# Download one Japanese voice embedding
# Add jf_alpha.safetensors to Resources/voices/
# Test synthesis with "こんにちは"
```

This validates the full pipeline (eSpeakNG → phonemes → model → audio) before investing in all voices.

1.7. **Extension context validation spike**

**Critical:** Validate eSpeakNG works in AudioUnit extension sandbox:
```swift
// Create a minimal test that runs IN the extension context
// (not just host app unit tests)
//
// 1. Build and install extension
// 2. Trigger synthesis via System Preferences → Spoken Content
// 3. Verify eSpeakNG data resources are accessible
// 4. Verify phonemization works in sandbox
```

**Why this matters:** AudioUnit extensions run in a restrictive sandbox. eSpeakNG's C library loads dictionary data from bundle resources. If bundle paths don't resolve correctly in extension context, non-English synthesis will fail silently.

**Validation steps:**
1. Add debug logging to eSpeakNGG2PProcessor for resource path resolution
2. Test via System Preferences (not unit tests)
3. Check Console.app for errors from extension process
4. If resources fail to load, add `espeak-ng-data` to extension bundle via project.yml

### Tests
- eSpeakNG can phonemize Japanese text
- eSpeakNG can phonemize Chinese text
- CompositeG2PProcessor routes English to Misaki
- CompositeG2PProcessor routes Japanese to eSpeakNG
- **Single Japanese voice produces audio (spike validation)**
- **eSpeakNG works in AudioUnit extension context (spike validation)**

### Acceptance Criteria
- [ ] Project builds without errors
- [ ] eSpeakNG phonemizes non-English text correctly
- [ ] Misaki still works for English
- [ ] Japanese spike produces audio
- [ ] Extension context spike validates eSpeakNG resources accessible

## Phase 2: Add Voice Definitions

**Goal:** Define all 54 voices in Constants.swift

### Tasks

2.1. **Add SupportedLanguage enum**
```swift
// Shared/Constants.swift
public enum SupportedLanguage: String, CaseIterable {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case japanese = "ja-JP"
    case mandarinChinese = "zh-CN"
    case spanish = "es-ES"
    case french = "fr-FR"
    case hindi = "hi-IN"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"

    var defaultVoiceId: String {
        switch self {
        case .americanEnglish: return "af_heart"
        case .britishEnglish: return "bf_emma"
        case .japanese: return "jf_alpha"
        case .mandarinChinese: return "zf_xiaobei"
        case .spanish: return "ef_dora"
        case .french: return "ff_siwis"
        case .hindi: return "hf_alpha"
        case .italian: return "if_sara"
        case .brazilianPortuguese: return "pf_dora"
        }
    }

    static func match(systemLanguage: String) -> SupportedLanguage? {
        // Exact match
        if let exact = SupportedLanguage(rawValue: systemLanguage) {
            return exact
        }
        // Base language fallback
        let base = systemLanguage.split(separator: "-").first.map(String.init) ?? systemLanguage
        switch base {
        case "en": return .americanEnglish
        case "ja": return .japanese
        case "zh": return .mandarinChinese
        case "es": return .spanish
        case "fr": return .french
        case "hi": return .hindi
        case "it": return .italian
        case "pt": return .brazilianPortuguese
        default: return nil
        }
    }
}
```

2.2. **Add missing English voices (10 total)**
```swift
// Add to availableVoices:
// en-US male (6 new)
VoiceDefinition(id: "am_eric", name: "Eric", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_fenrir", name: "Fenrir", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_liam", name: "Liam", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_onyx", name: "Onyx", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_puck", name: "Puck", language: "en-US", gender: .male, quality: .b),
VoiceDefinition(id: "am_santa", name: "Santa", language: "en-US", gender: .male, quality: .b),

// en-GB female (2 new)
VoiceDefinition(id: "bf_isabella", name: "Isabella", language: "en-GB", gender: .female, quality: .b),
VoiceDefinition(id: "bf_lily", name: "Lily", language: "en-GB", gender: .female, quality: .b),

// en-GB male (2 new)
VoiceDefinition(id: "bm_fable", name: "Fable", language: "en-GB", gender: .male, quality: .b),
VoiceDefinition(id: "bm_lewis", name: "Lewis", language: "en-GB", gender: .male, quality: .b),
```

2.3. **Add non-English voices (26 total)**
```swift
// Japanese (5)
VoiceDefinition(id: "jf_alpha", name: "Alpha", language: "ja-JP", gender: .female, quality: .b),
VoiceDefinition(id: "jf_gongitsune", name: "Gongitsune", language: "ja-JP", gender: .female, quality: .b),
VoiceDefinition(id: "jf_nezumi", name: "Nezumi", language: "ja-JP", gender: .female, quality: .b),
VoiceDefinition(id: "jf_tebukuro", name: "Tebukuro", language: "ja-JP", gender: .female, quality: .b),
VoiceDefinition(id: "jm_kumo", name: "Kumo", language: "ja-JP", gender: .male, quality: .b),

// Chinese (8)
VoiceDefinition(id: "zf_xiaobei", name: "Xiaobei", language: "zh-CN", gender: .female, quality: .b),
VoiceDefinition(id: "zf_xiaoni", name: "Xiaoni", language: "zh-CN", gender: .female, quality: .b),
VoiceDefinition(id: "zf_xiaoxiao", name: "Xiaoxiao", language: "zh-CN", gender: .female, quality: .b),
VoiceDefinition(id: "zf_xiaoyi", name: "Xiaoyi", language: "zh-CN", gender: .female, quality: .b),
VoiceDefinition(id: "zm_yunjian", name: "Yunjian", language: "zh-CN", gender: .male, quality: .b),
VoiceDefinition(id: "zm_yunxi", name: "Yunxi", language: "zh-CN", gender: .male, quality: .b),
VoiceDefinition(id: "zm_yunxia", name: "Yunxia", language: "zh-CN", gender: .male, quality: .b),
VoiceDefinition(id: "zm_yunyang", name: "Yunyang", language: "zh-CN", gender: .male, quality: .b),

// Spanish (3)
VoiceDefinition(id: "ef_dora", name: "Dora", language: "es-ES", gender: .female, quality: .b),
VoiceDefinition(id: "em_alex", name: "Alex", language: "es-ES", gender: .male, quality: .b),
VoiceDefinition(id: "em_santa", name: "Santa", language: "es-ES", gender: .male, quality: .b),

// French (1)
VoiceDefinition(id: "ff_siwis", name: "Siwis", language: "fr-FR", gender: .female, quality: .b),

// Hindi (4)
VoiceDefinition(id: "hf_alpha", name: "Alpha", language: "hi-IN", gender: .female, quality: .b),
VoiceDefinition(id: "hf_beta", name: "Beta", language: "hi-IN", gender: .female, quality: .b),
VoiceDefinition(id: "hm_omega", name: "Omega", language: "hi-IN", gender: .male, quality: .b),
VoiceDefinition(id: "hm_psi", name: "Psi", language: "hi-IN", gender: .male, quality: .b),

// Italian (2)
VoiceDefinition(id: "if_sara", name: "Sara", language: "it-IT", gender: .female, quality: .b),
VoiceDefinition(id: "im_nicola", name: "Nicola", language: "it-IT", gender: .male, quality: .b),

// Portuguese (3)
VoiceDefinition(id: "pf_dora", name: "Dora", language: "pt-BR", gender: .female, quality: .b),
VoiceDefinition(id: "pm_alex", name: "Alex", language: "pt-BR", gender: .male, quality: .b),
VoiceDefinition(id: "pm_santa", name: "Santa", language: "pt-BR", gender: .male, quality: .b),
```

2.4. **Update defaultEnabledVoiceIds**
```swift
public static var defaultEnabledVoiceIds: [String] {
    SupportedLanguage.allCases.map { $0.defaultVoiceId }
}
```

2.5. **Add VoiceConfiguration validation**
```swift
// Shared/VoiceConfiguration.swift
public var enabledVoiceIds: [String] {
    let stored = userDefaults.stringArray(forKey: Constants.voicesKey) ?? []
    let validIds = Set(Constants.availableVoices.map { $0.id })
    let validated = stored.filter { validIds.contains($0) }
    return validated.isEmpty ? Constants.defaultEnabledVoiceIds : validated
}
```

### Tests
- All 54 voice definitions have unique IDs
- SupportedLanguage.match() handles all variants
- Default voice exists for each language
- VoiceConfiguration filters unknown IDs

### Acceptance Criteria
- [ ] 54 voices defined in Constants.swift
- [ ] No duplicate voice IDs
- [ ] Default voice per language works

## Phase 3: Download Voice Embeddings

**Goal:** Add all voice embedding files to project

**Inventory clarification:**
- **Current state:** 18 English voices already in repo (af_heart, af_bella, etc.)
- **To download:** 36 new voices (10 missing English + 26 non-English)
- **Final state:** 54 total voice embeddings in `Resources/voices/`

### Tasks

3.1. **Download embeddings from Hugging Face**
```bash
# Update scripts/download-models.sh to include all 54 voices
# Download 36 new files from mlx-community format (safetensors)
# Existing 18 English voices remain unchanged
```

3.2. **Update project.yml for Shared framework resources**
```yaml
targets:
  KokoroVoiceShared:
    sources:
      - path: Shared
      - path: Resources/voices
        buildPhase: resources
```

3.3. **Create checksums.txt**
```bash
# Generate SHA256 checksums for all voice files
cd Resources/voices
shasum -a 256 *.safetensors > checksums.txt
```

3.4. **Add build-time validation script**
```bash
#!/bin/bash
# scripts/validate-voices.sh
VOICES_DIR="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Resources/voices"
# Validate all expected voices exist
```

3.5. **Integrate validation script into build process**

**Where the script runs:**

1. **Xcode Build Phase** (required for both app and extension):
   ```yaml
   # project.yml - add to both targets
   targets:
     KokoroVoice:
       postBuildScripts:
         - script: "${PROJECT_DIR}/scripts/validate-voices.sh"
           name: "Validate Voice Embeddings"

     KokoroVoiceExtension:
       postBuildScripts:
         - script: "${PROJECT_DIR}/scripts/validate-voices.sh"
           name: "Validate Voice Embeddings"
   ```

2. **CI Pipeline** (checksum validation):
   ```yaml
   # GitHub Actions / CI config
   - name: Validate voice checksums
     run: |
       cd Resources/voices
       shasum -a 256 -c checksums.txt
   ```

**Behavior:**
- Local builds: script validates file presence, fails build if missing
- CI builds: additionally validates checksums before release builds
- Both app and extension targets run validation independently

### Tests
- All 54 .safetensors files exist
- File sizes are reasonable (100-200KB each)
- Checksums match

### Acceptance Criteria
- [ ] 54 voice embedding files in Resources/voices/
- [ ] Files included in Shared framework bundle
- [ ] Build validation passes for both app and extension targets
- [ ] CI pipeline validates checksums

## Error Behavior Specification

Define how each failure mode is handled:

| Scenario | Engine Behavior | AudioUnit Behavior | User Experience |
|----------|-----------------|-------------------|-----------------|
| Unknown voice ID | Throw `voiceEmbeddingLoadError` | Catch, log, signal error | VoiceOver announces error |
| Missing embedding file | Fallback: language default → af_heart → throw | Catch, log, signal error | User hears fallback voice (or error if af_heart missing) |
| Unsupported language | Return `nil` from match(), synthesis fails | Catch, log, signal error | VoiceOver announces error |
| G2P failure | Throw from composite processor | Catch, log, signal error | VoiceOver announces error |
| Empty text | Return empty audio buffer | Return empty buffer | Silent, no announcement |
| eSpeakNG init failure | Use Misaki for English, fail non-English | Log warning | Non-English voices don't work |
| Concurrent eSpeakNG calls | Serial queue ensures thread-safety | N/A | No impact (handled internally) |

**Fallback chain:** Requested voice → Language default → af_heart (last resort) → Hard error

**Key principle:** Never crash. Always log. Surface errors to system so VoiceOver can announce.

## Phase 4: Update Engine

**Goal:** Make KokoroEngine support multi-language synthesis

### Tasks

4.1. **Update KokoroEngine to use composite G2P**
```swift
// Shared/KokoroEngine.swift
// Change from:
tts = try KokoroTTS(modelPath: modelFile, g2p: .misaki)
// To:
tts = try KokoroTTS(modelPath: modelFile, g2p: .composite)
```

4.2. **Add voice embedding caching and loading**

**Performance consideration:** Loading `.safetensors` files is expensive (~10-50ms per file). Since KokoroEngine is an actor, we can safely cache loaded embeddings.

```swift
// KokoroEngine.swift - voice embedding cache
private var voiceEmbeddingCache: [String: MLXArray] = [:]
private let maxCacheSize = 5  // Keep 5 most recently used voices in memory

func loadVoiceEmbedding(voiceId: String, language: String) async throws -> MLXArray {
    // 1. Check cache first
    if let cached = voiceEmbeddingCache[voiceId] {
        return cached
    }

    let bundle = Bundle(for: KokoroEngine.self)

    // Validate voice ID
    guard Constants.availableVoices.contains(where: { $0.id == voiceId }) else {
        throw KokoroEngineError.voiceEmbeddingLoadError("Unknown voice: \(voiceId)")
    }

    // 2. Try requested voice
    if let path = bundle.path(forResource: voiceId, ofType: "safetensors", inDirectory: "voices") {
        let embedding = try await loadSafetensors(from: path)
        cacheVoiceEmbedding(voiceId, embedding: embedding)
        return embedding
    }

    // 3. Try language default
    if let lang = SupportedLanguage(rawValue: language) {
        let defaultId = lang.defaultVoiceId
        if defaultId != voiceId,
           let path = bundle.path(forResource: defaultId, ofType: "safetensors", inDirectory: "voices") {
            print("KokoroEngine: Using \(defaultId) as fallback for \(voiceId)")
            let embedding = try await loadSafetensors(from: path)
            cacheVoiceEmbedding(defaultId, embedding: embedding)
            return embedding
        }
    }

    // 4. Last resort: af_heart (per spec fallback chain)
    if voiceId != "af_heart",
       let fallbackPath = bundle.path(forResource: "af_heart", ofType: "safetensors", inDirectory: "voices") {
        print("KokoroEngine: Using af_heart as last resort fallback")
        let embedding = try await loadSafetensors(from: fallbackPath)
        cacheVoiceEmbedding("af_heart", embedding: embedding)
        return embedding
    }

    // 5. Hard failure - no valid voice found
    throw KokoroEngineError.voiceEmbeddingLoadError("Voice \(voiceId) not found and no fallback available")
}

private func cacheVoiceEmbedding(_ voiceId: String, embedding: MLXArray) {
    // LRU eviction: remove oldest if at capacity
    if voiceEmbeddingCache.count >= maxCacheSize {
        // Simple FIFO eviction (could enhance with access timestamps)
        if let oldest = voiceEmbeddingCache.keys.first {
            voiceEmbeddingCache.removeValue(forKey: oldest)
        }
    }
    voiceEmbeddingCache[voiceId] = embedding
}
```

**Cache characteristics:**
- **Size:** 5 voices (~500KB-1MB total memory)
- **Thread-safety:** Actor isolation guarantees no races
- **Eviction:** Simple FIFO (sufficient for typical usage patterns)
- **Lifetime:** Cleared when engine is deinitialized

4.3. **Update synthesize method to accept language**
```swift
public func synthesize(text: String, voiceId: String, language: String) async throws -> [Float] {
    // Set G2P language
    let lang = Language(rawValue: language) ?? .americanEnglish
    // ... synthesis logic
}
```

### Tests
- Synthesis works for each of 9 languages
- Fallback chain works correctly
- Error handling for missing voices

### Acceptance Criteria
- [ ] Japanese synthesis produces audio
- [ ] Chinese synthesis produces audio
- [ ] All 9 languages work
- [ ] Fallback to default voice works

## Phase 5: Update AudioUnit

**Goal:** Register all voices with system

### Tasks

5.1. **Update speechVoices property with eSpeakNG availability gating**

**Critical:** If eSpeakNG initialization fails, DO NOT register non-English voices with the system. This prevents users from selecting voices that cannot synthesize.

```swift
// KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift

// Track eSpeakNG availability at init time
private static var eSpeakNGAvailable: Bool = {
    do {
        let _ = try eSpeakNGG2PProcessor()
        return true
    } catch {
        print("KokoroVoice: eSpeakNG unavailable, non-English voices disabled")
        return false
    }
}()

public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
    let enabledVoiceIds = VoiceConfiguration.shared.enabledVoiceIds
    return Constants.availableVoices
        .filter { voice in
            // Must be enabled by user
            guard enabledVoiceIds.contains(voice.id) else { return false }

            // Gate non-English voices if eSpeakNG unavailable
            if !Self.eSpeakNGAvailable {
                let isEnglish = voice.language == "en-US" || voice.language == "en-GB"
                if !isEnglish { return false }
            }
            return true
        }
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

**Behavior:** When eSpeakNG fails to init:
- English voices continue to work (Misaki handles them)
- Non-English voices are filtered out of system registration
- No "broken" voices appear in System Preferences
- User experience: limited functionality, but no silent failures

5.2. **Update synthesizeSpeechRequest to pass language**
```swift
override public func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
    let voiceId = request.voice.identifier.replacingOccurrences(
        of: Constants.voiceIdentifierPrefix, with: ""
    )

    guard let voiceDef = Constants.voiceDefinition(forId: voiceId) else {
        // Unknown voice
        return
    }

    let language = voiceDef.language
    // Pass language to engine
}
```

5.3. **GPL-3.0 Compliance**

eSpeakNG is GPL-3.0 licensed. Required compliance steps with **specific file locations**:

1. **Include license text**
   - Create: `KokoroVoice/Resources/COPYING-GPL3.txt` (full GPL-3.0 text)
   - Include in app bundle via project.yml resources
   - Both host app and extension get the license automatically (linked framework)

2. **Attribution in Credits**
   - Create or update: `KokoroVoice/Resources/Credits.rtf`
   - Content:
   ```
   This app uses:
   - Kokoro-82M voice model (Apache-2.0, hexgrad)
   - eSpeakNG text-to-phoneme engine (GPL-3.0, espeak-ng project)

   Source code for this application available at:
   https://github.com/[repo-url]
   ```

3. **project.yml integration**
   ```yaml
   targets:
     KokoroVoice:
       sources:
         - path: KokoroVoice/Resources/Credits.rtf
           buildPhase: resources
         - path: KokoroVoice/Resources/COPYING-GPL3.txt
           buildPhase: resources
   ```

4. **Source availability** - Ensure project repo is public or provide written offer for source

**Note:** Legal review required before v1.0 public release. For beta testing, GPL compliance is straightforward since source is available.

### Tests
- Voices appear in System Preferences
- VoiceOver can select non-English voices
- Voice count matches enabled voices

### Acceptance Criteria
- [ ] All enabled voices appear in System Preferences
- [ ] VoiceOver works with Japanese voices
- [ ] GPL attribution present

## Phase 6: Testing & Validation

**Goal:** Comprehensive testing across all languages

### Tasks

6.1. **Unit tests**
- Voice definition uniqueness
- Language matching (all BCP-47 variants including edge cases):
  - `zh-Hans` → zh-CN
  - `zh-Hant` → zh-CN (documented limitation)
  - `pt-PT` → pt-BR
  - `en-AU` → en-US
  - `es-MX` → es-ES
- VoiceConfiguration validation
- Fallback chain logic
- **eSpeakNG availability gating**: verify non-English voices excluded when eSpeakNG unavailable

6.2. **Integration tests (CI-safe strategy)**

**Test categorization:**
- **Fast tests** (run on every PR): G2P routing, voice loading, language matching
- **Slow tests** (run on dedicated lane): Full synthesis with audio validation

```swift
// Mark heavy synthesis tests for dedicated CI lane
// These require model files and take significant time
@available(*, message: "Run only on synthesis-test CI lane")
final class SynthesisIntegrationTests: XCTestCase {

    func testSynthesizeAllLanguages() async throws {
        let engine = KokoroEngine.shared
        let testPhrases: [(String, String, String)] = [
            ("en-US", "af_heart", "Hello world"),
            ("ja-JP", "jf_alpha", "こんにちは"),
            ("zh-CN", "zf_xiaobei", "你好世界"),
            ("es-ES", "ef_dora", "Hola mundo"),
            ("fr-FR", "ff_siwis", "Bonjour"),
            ("hi-IN", "hf_alpha", "नमस्ते"),
            ("it-IT", "if_sara", "Ciao"),
            ("pt-BR", "pf_dora", "Olá"),
        ]

        for (language, voiceId, text) in testPhrases {
            let audio = try await engine.synthesize(text: text, voiceId: voiceId, language: language)
            // Stronger assertions than just length
            XCTAssertGreaterThan(audio.count, 1000, "Audio too short for \(language)")
            XCTAssertTrue(audio.contains { $0 != 0 }, "Audio is all zeros for \(language)")
        }
    }
}
```

**CI configuration (concrete for this repo):**

Since this repo currently has no CI, we define a practical approach:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: macos-14  # Apple Silicon (M1/M2)
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Run fast tests
        run: |
          cd KokoroVoice
          swift test --filter "!SynthesisIntegrationTests"

  synthesis-tests:
    runs-on: macos-14
    timeout-minutes: 60  # Allow for slow CPU inference
    if: github.ref == 'refs/heads/main'  # Only on main, not PRs
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true  # Required for model files
      - name: Run synthesis tests
        run: |
          cd KokoroVoice
          swift test --filter "SynthesisIntegrationTests"
```

**Why this approach:**
- **macos-14** is the standard macOS runner (no "xlarge" needed - CPU inference works)
- **synthesis-tests on main only** prevents slow PR feedback loops
- **60-minute timeout** accounts for CPU-only model inference
- **Git LFS** required since model files are large
- **No GPU** required - MLX runs on CPU for testing (slower but functional)
```

6.3. **Manual testing checklist**
- [ ] Japanese voice in System Preferences
- [ ] Chinese voice with VoiceOver
- [ ] Spanish voice with Live Speech
- [ ] Voice switching between languages
- [ ] Fallback when voice disabled

### Acceptance Criteria
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing complete

## File Changes Summary

| File | Action | Lines |
|------|--------|-------|
| `LocalPackages/kokoro-ios/Package.swift` | Modify | +3 |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/Language.swift` | Modify | +10 |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/CompositeG2PProcessor.swift` | Create | ~50 |
| `LocalPackages/kokoro-ios/Sources/KokoroSwift/TextProcessing/G2PFactory.swift` | Modify | +5 |
| `Shared/Constants.swift` | Modify | +100 |
| `Shared/KokoroEngine.swift` | Modify | +30 |
| `Shared/VoiceConfiguration.swift` | Modify | +10 |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Modify | +10 |
| `Resources/voices/*.safetensors` | Create | 36 files |
| `project.yml` | Modify | +5 |
| `Tests/` | Modify | +50 |

**Total:** ~200 new lines, ~100 modified lines, 36 new resource files

## Risk Mitigation

| Risk | Priority | Mitigation |
|------|----------|------------|
| **GPL-3.0 compliance** | CRITICAL | Include license text, ensure source availability, legal review before v1.0 |
| eSpeakNG build fails | High | Test build early in Phase 1; have fallback to English-only |
| **eSpeakNG thread-safety** | High | **Proactive:** Create serial queue for all eSpeakNG calls. The C library uses global state. |
| **eSpeakNG extension sandbox** | High | **Validate in Phase 1 spike:** Test eSpeakNG data resources accessible from AudioUnit context |
| Language tag edge cases | Medium | Test `zh-Hans`, `pt-PT`, `en-AU` variants; document expected routing |
| Voice quality varies | Low | Document quality grades; user can disable low-quality voices |
| App size too large | Low | ~5-10MB acceptable; on-demand download is future work |

## Dependencies

- eSpeakNGSwift ^1.0.1
- Voice embeddings from hexgrad/Kokoro-82M (mlx-community format)
