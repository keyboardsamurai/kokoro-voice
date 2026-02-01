# Research: GPL-Free G2P Alternatives for Spec 0003

## Context

eSpeakNG is GPL-3.0 licensed, which is unacceptable for this project. We need permissively-licensed alternatives for non-English G2P (Grapheme-to-Phoneme) conversion.

**Constraint:** Kokoro-82M was trained with espeak-ng IPA phonemes. Any alternative must produce compatible IPA output.

## Languages Required

| Language | Code | Voices | Complexity |
|----------|------|--------|------------|
| Japanese | ja-JP | 5 | High (kanji readings, pitch accent) |
| Mandarin Chinese | zh-CN | 8 | High (tones, heteronyms) |
| Spanish | es-ES | 3 | Low (regular orthography) |
| French | fr-FR | 1 | Medium (liaisons, silent letters) |
| Hindi | hi-IN | 4 | Medium (Devanagari script) |
| Italian | it-IT | 2 | Low (regular orthography) |
| Brazilian Portuguese | pt-BR | 3 | Low-Medium (some irregularities) |

## Option Analysis

### Option 1: Gruut (MIT License)

**Source:** [github.com/rhasspy/gruut](https://github.com/rhasspy/gruut)

**Supported Languages:** Arabic, Catalan, Czech, German, Spanish, Farsi, French, Italian, Luxembourgish, Dutch, Portuguese, Russian, Swedish, Swahili

**Coverage for our needs:**
- ✅ Spanish, French, Italian, Portuguese
- ❌ Japanese, Chinese, Hindi

**Integration:** Python library - would need subprocess or embedded Python

**Pros:**
- MIT licensed
- High quality, actively maintained
- Produces IPA output
- Supports SSML

**Cons:**
- Python dependency (subprocess overhead)
- Missing Japanese, Chinese, Hindi
- Need to verify IPA format matches espeak-ng

### Option 2: Language-Specific Native Libraries

#### Japanese: MeCab + Phoneme Mapping

**Source:** [github.com/shinjukunian/Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift)

**License:** BSD (triple-licensed BSD/GPL/LGPL - we choose BSD)

**How it works:**
1. MeCab tokenizes Japanese text and provides readings (hiragana/katakana)
2. Map kana to IPA phonemes (straightforward 1:1 mapping)

**Pros:**
- Native Swift via SPM
- BSD licensed
- Fast, well-tested
- Used in production apps (Furiganify, FuriganaPDF)

**Cons:**
- Need to build kana→IPA mapping layer
- Dictionary files are large (~50MB)
- Pitch accent not included (would need additional data)

#### Chinese: HanziPinyin (Native Swift)

**Source:** [github.com/teambition/HanziPinyin](https://github.com/teambition/HanziPinyin)

**License:** MIT

**How it works:**
1. Convert Chinese characters to pinyin (with tone numbers)
2. Map pinyin+tones to IPA phonemes

**Pros:**
- Native Swift
- MIT licensed
- Lightweight
- Supports Traditional and Simplified

**Cons:**
- Need to build pinyin→IPA mapping layer
- Heteronym handling may need work
- Tone markers need conversion to IPA format

#### Romance Languages: Rule-Based Swift

**Approach:** Build simple rule-based converters for Spanish, French, Italian, Portuguese

**Pros:**
- No external dependencies
- Full control over output format
- Very fast
- Regular orthography makes this tractable

**Cons:**
- Development effort required
- Need linguistic expertise for edge cases
- French has more irregularities than others

#### Hindi: Devanagari Transliteration

**Approach:** Map Devanagari script to IPA (mostly regular)

**Pros:**
- Devanagari is largely phonetic
- Straightforward mapping possible

**Cons:**
- Need to handle schwa deletion rules
- Some dialectal variations

### Option 3: Neural G2P Models (CoreML)

**Approach:** Train or adapt a transformer-based G2P model, run via CoreML

**Sources:**
- [Transformer-based G2P papers](https://arxiv.org/abs/2004.06338)
- Could train on permissively-licensed lexicon data

**Pros:**
- Single unified model for all languages
- No C library linking
- Could run on Neural Engine
- Portable

**Cons:**
- Significant training effort
- Need permissively-licensed training data
- Model size/latency concerns
- Quality may be lower than specialized tools

### Option 4: IPC Isolation (eSpeakNG in Separate Process)

**Approach:** Run eSpeakNG as a separate helper process, communicate via IPC

**Legal Theory:** GPL obligations might be limited to the helper process if it's a separate program

**Pros:**
- Uses proven eSpeakNG quality
- Minimal code changes from original plan

**Cons:**
- **Legally murky** - needs lawyer review
- IPC overhead (latency)
- Process management complexity
- May still trigger GPL obligations (derivative work arguments)

**Recommendation:** Avoid this option due to legal uncertainty

### Option 5: Hybrid Approach (RECOMMENDED)

**Strategy:** Use the best tool for each language family:

| Language | G2P Engine | License |
|----------|------------|---------|
| English | Misaki (existing) | MIT |
| Japanese | MeCab-Swift + kana→IPA | BSD |
| Chinese | HanziPinyin + pinyin→IPA | MIT |
| Spanish, French, Italian, Portuguese | Gruut (subprocess) OR rule-based | MIT |
| Hindi | Devanagari→IPA mapping | Custom |

**Implementation:**

```swift
final class HybridG2PProcessor: G2PProcessor {
    private let misakiProcessor: MisakiG2PProcessor  // English
    private let mecabProcessor: MeCabG2PProcessor?   // Japanese
    private let pinyinProcessor: PinyinG2PProcessor? // Chinese
    private let romanceProcessor: RomanceG2PProcessor? // es/fr/it/pt
    private let hindiProcessor: HindiG2PProcessor?   // Hindi

    func process(text: String, language: Language) throws -> String {
        switch language {
        case .americanEnglish, .britishEnglish:
            return try misakiProcessor.process(text)
        case .japanese:
            return try mecabProcessor?.process(text) ?? ""
        case .mandarinChinese:
            return try pinyinProcessor?.process(text) ?? ""
        case .spanish, .french, .italian, .brazilianPortuguese:
            return try romanceProcessor?.process(text, language: language) ?? ""
        case .hindi:
            return try hindiProcessor?.process(text) ?? ""
        }
    }
}
```

**Pros:**
- All permissive licenses (MIT/BSD)
- Native Swift where possible (MeCab, HanziPinyin)
- Best quality for each language
- No GPL concerns

**Cons:**
- More complex architecture
- Need to build IPA mapping layers
- Need to verify phoneme compatibility with Kokoro

## IPA Compatibility Concern

**Critical:** Kokoro was trained with espeak-ng phonemes. We need to ensure our alternative outputs match.

**Mitigation:**
1. Create test suite comparing alternative output vs espeak-ng output
2. Build normalization layer if needed
3. Test audio quality for each language before shipping

**Example phoneme comparison needed:**
```
Japanese "こんにちは":
  espeak-ng: [phonemes here]
  MeCab+mapping: [phonemes here]
  → Must match or be mapped
```

## Recommendation

**Adopt Option 5 (Hybrid Approach)** with this implementation order:

### Phase 1: Japanese + Chinese (Native Swift)
1. Integrate MeCab-Swift (BSD)
2. Build kana→IPA mapping
3. Integrate HanziPinyin (MIT)
4. Build pinyin→IPA mapping
5. Test phoneme compatibility

### Phase 2: Romance Languages
1. Start with rule-based Spanish (most regular)
2. Extend to Italian, Portuguese
3. Add French (most complex)
4. OR: Use Gruut subprocess if rules prove too complex

### Phase 3: Hindi
1. Build Devanagari→IPA mapper
2. Handle schwa deletion rules
3. Test and refine

### Fallback Strategy

If a language's alternative G2P produces poor quality:
1. Disable that language temporarily
2. Research additional alternatives
3. Consider contributing to Gruut to add missing languages

## Size Impact

| Component | Size Estimate |
|-----------|---------------|
| MeCab dictionary | ~50MB |
| HanziPinyin data | ~2MB |
| Romance rules | <100KB |
| Hindi mapping | <500KB |
| **Total additional** | ~53MB |

This is significant but acceptable for a desktop app. Could offer language packs for download if needed.

## Decision Required

Before proceeding:
1. Confirm hybrid approach is acceptable
2. Prioritize which languages to implement first
3. Accept increased complexity vs original eSpeakNG plan
4. Accept potential quality differences (to be tested)
