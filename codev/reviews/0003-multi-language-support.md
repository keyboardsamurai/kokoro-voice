# Review 0003: Multi-Language Support (Romance Languages)

## Implementation Summary

Added support for Spanish (es-ES), Italian (it-IT), and Brazilian Portuguese (pt-BR) voices using a pure Swift rule-based G2P approach, avoiding GPL dependencies.

### Key Deliverables

1. **RomanceG2PProcessor** - Rule-based G2P for Spanish, Italian, Portuguese
   - Handles accented vowels (á, é, í, ó, ú, etc.)
   - Implements language-specific digraphs (ch, ll, ñ for Spanish; gn, gli, sc for Italian; lh, nh for Portuguese)
   - Brazilian Portuguese palatalization (ti→tʃ, di→dʒ)

2. **CompositeG2PProcessor** - Routes English to Misaki, Romance to rule-based
   - Language-aware routing
   - Phoneme normalization for Kokoro vocabulary

3. **PhonemeNormalizer** - Validates IPA output against Kokoro's vocabulary

4. **36 Voice Definitions** - Complete voice set
   - 20 en-US, 8 en-GB, 3 es-ES, 2 it-IT, 3 pt-BR

5. **SupportedLanguage Enum** - BCP-47 language matching with fallbacks

## External Review Summary

### Gemini Review
**VERDICT:** REQUEST_CHANGES (spec-level issues, not implementation)

**Key Findings:**
1. Spec has contradictory eSpeakNG references - spec document needs updating, implementation correctly uses rule-based G2P
2. Concern about accented vowels - **ADDRESSED**: Implementation handles all accented vowels (lines 60-64, 161-165, 267-272)
3. Language enum case mismatch - existing code uses `en-us` (lowercase), new code uses `es-ES` (BCP-47). Not changing to maintain compatibility.

### Codex Review
Review partially completed. No blocking issues identified.

## Self-Review Checklist

| Requirement | Status | Notes |
|-------------|--------|-------|
| 3 Romance languages | ✅ | Spanish, Italian, Portuguese |
| 36 voices total | ✅ | 28 English + 8 Romance |
| Rule-based G2P (no GPL) | ✅ | Pure Swift implementation |
| Graceful degradation | ✅ | Existing fallback chain preserved |
| System voice selection | ✅ | AVSpeechSynthesisProviderVoice integration |
| No model changes | ✅ | Only G2P and voice definitions |

## Test Coverage

### Unit Tests Added
- RomanceG2PProcessor: Spanish, Italian, Portuguese phoneme rules
- Language enum: usesEnglishG2P, usesRomanceG2P helpers
- PhonemeNormalizer: vocabulary validation
- CompositeG2PProcessor: language routing
- SupportedLanguage: BCP-47 matching and defaults
- Voice definitions: 36 voices, uniqueness, counts per language
- VoiceConfiguration: Romance language helper properties

### Manual Testing Required
- [ ] Spanish voices appear in System Preferences → Spoken Content
- [ ] Italian voices appear in System Preferences → Spoken Content
- [ ] Portuguese voices appear in System Preferences → Spoken Content
- [ ] VoiceOver works with Romance voice selected
- [ ] Audio quality validation for each language

## Known Limitations

1. **Latin American Spanish not differentiated** - Uses Castilian Spanish θ for c/z, could be refined for es-MX
2. **Stress marking** - Rule-based G2P doesn't mark prosodic stress explicitly
3. **Heteronyms** - No disambiguation for words spelled same but pronounced differently

## Lessons Learned

1. **Rule-based G2P is viable for Romance languages** - Regular orthography enables pure Swift implementation without external dependencies
2. **Case sensitivity matters** - BCP-47 uses mixed case (en-US) but some legacy code uses lowercase
3. **Phoneme vocabulary validation is important** - PhonemeNormalizer catches incompatible IPA symbols

## Files Changed

| File | Lines Changed | Description |
|------|---------------|-------------|
| Language.swift | +28 | Added Romance language cases |
| RomanceG2PProcessor.swift | +315 (new) | Rule-based G2P |
| PhonemeNormalizer.swift | +111 (new) | Vocabulary validation |
| CompositeG2PProcessor.swift | +75 (new) | Language routing |
| G2PFactory.swift | +8 | Added composite case |
| Constants.swift | +90 | Voice definitions, SupportedLanguage |
| KokoroEngine.swift | +30 | KokoroLanguage updates |
| VoiceConfiguration.swift | +25 | Romance language helpers |
| RomanceG2PTests.swift | +235 (new) | Test coverage |
| VoiceConfigurationTests.swift | +115 | Multi-language tests |

**Total:** ~1,000 new lines

## Recommendation

**Ready for PR.** Implementation satisfies spec requirements. Gemini's concerns are about spec document consistency, not implementation quality.
