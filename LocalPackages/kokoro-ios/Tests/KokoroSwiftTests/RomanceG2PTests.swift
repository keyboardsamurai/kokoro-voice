import Testing
@testable import KokoroSwift

// MARK: - Romance G2P Processor Tests

@Suite("Romance G2P Processor")
struct RomanceG2PProcessorTests {

    // MARK: - Language Support Tests

    @Test("Processor supports Romance languages")
    func processorSupportsRomanceLanguages() throws {
        let processor = RomanceG2PProcessor()

        try processor.setLanguage(.spanish)
        try processor.setLanguage(.italian)
        try processor.setLanguage(.brazilianPortuguese)
    }

    @Test("Processor rejects non-Romance languages")
    func processorRejectsNonRomanceLanguages() {
        let processor = RomanceG2PProcessor()

        #expect(throws: G2PProcessorError.self) {
            try processor.setLanguage(.enUS)
        }

        #expect(throws: G2PProcessorError.self) {
            try processor.setLanguage(.enGB)
        }
    }

    @Test("Processor throws when not initialized")
    func processorThrowsWhenNotInitialized() {
        let processor = RomanceG2PProcessor()

        #expect(throws: G2PProcessorError.processorNotInitialized) {
            _ = try processor.process(input: "Hola mundo")
        }
    }

    // MARK: - Spanish G2P Tests

    @Test("Spanish basic phonemes")
    func spanishBasicPhonemes() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let (result, _) = try processor.process(input: "hola")
        #expect(!result.isEmpty)
        #expect(result.contains("o"))  // 'o' should be preserved
        #expect(result.contains("l"))  // 'l' should be preserved
        #expect(result.contains("a"))  // 'a' should be preserved
    }

    @Test("Spanish silent h")
    func spanishSilentH() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let (result, _) = try processor.process(input: "hola")
        // 'h' should be silent, not appear in output
        #expect(!result.contains("h"))
    }

    @Test("Spanish ch digraph")
    func spanishChDigraph() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let (result, _) = try processor.process(input: "chocolate")
        #expect(result.contains("tʃ"))  // ch → tʃ
    }

    @Test("Spanish ñ")
    func spanishNye() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let (result, _) = try processor.process(input: "español")
        #expect(result.contains("ɲ"))  // ñ → ɲ
    }

    @Test("Spanish j and g before e/i")
    func spanishJotaSound() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let (jResult, _) = try processor.process(input: "jota")
        #expect(jResult.contains("x"))  // j → x

        let (gResult, _) = try processor.process(input: "gente")
        #expect(gResult.contains("x"))  // ge → x
    }

    // MARK: - Italian G2P Tests

    @Test("Italian basic phonemes")
    func italianBasicPhonemes() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.italian)

        let (result, _) = try processor.process(input: "ciao")
        #expect(!result.isEmpty)
        #expect(result.contains("tʃ"))  // ci → tʃ
    }

    @Test("Italian sc before e/i")
    func italianSceFricative() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.italian)

        let (result, _) = try processor.process(input: "scena")
        #expect(result.contains("ʃ"))  // sc+e → ʃ
    }

    @Test("Italian gn digraph")
    func italianGnDigraph() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.italian)

        let (result, _) = try processor.process(input: "gnocchi")
        #expect(result.contains("ɲ"))  // gn → ɲ
    }

    @Test("Italian gli trigraph")
    func italianGliTrigraph() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.italian)

        let (result, _) = try processor.process(input: "figli")
        #expect(result.contains("ʎ"))  // gli → ʎ
    }

    // MARK: - Portuguese G2P Tests

    @Test("Portuguese basic phonemes")
    func portugueseBasicPhonemes() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.brazilianPortuguese)

        let (result, _) = try processor.process(input: "olá")
        #expect(!result.isEmpty)
    }

    @Test("Portuguese ch digraph")
    func portugueseChDigraph() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.brazilianPortuguese)

        let (result, _) = try processor.process(input: "chocolate")
        #expect(result.contains("ʃ"))  // ch → ʃ
    }

    @Test("Portuguese lh digraph")
    func portugueseLhDigraph() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.brazilianPortuguese)

        let (result, _) = try processor.process(input: "filho")
        #expect(result.contains("ʎ"))  // lh → ʎ
    }

    @Test("Portuguese nh digraph")
    func portugueseNhDigraph() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.brazilianPortuguese)

        let (result, _) = try processor.process(input: "banho")
        #expect(result.contains("ɲ"))  // nh → ɲ
    }

    @Test("Brazilian Portuguese t before i")
    func brazilianTBeforeI() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.brazilianPortuguese)

        let (result, _) = try processor.process(input: "tipo")
        #expect(result.contains("tʃ"))  // ti → tʃ (Brazilian)
    }
}

// MARK: - Language Enum Tests

@Suite("Language Enum")
struct LanguageTests {

    @Test("Language uses English G2P")
    func languageUsesEnglishG2P() {
        #expect(Language.enUS.usesEnglishG2P)
        #expect(Language.enGB.usesEnglishG2P)
        #expect(!Language.spanish.usesEnglishG2P)
        #expect(!Language.italian.usesEnglishG2P)
        #expect(!Language.brazilianPortuguese.usesEnglishG2P)
    }

    @Test("Language uses Romance G2P")
    func languageUsesRomanceG2P() {
        #expect(!Language.enUS.usesRomanceG2P)
        #expect(!Language.enGB.usesRomanceG2P)
        #expect(Language.spanish.usesRomanceG2P)
        #expect(Language.italian.usesRomanceG2P)
        #expect(Language.brazilianPortuguese.usesRomanceG2P)
    }

    @Test("Language raw values are BCP-47")
    func languageRawValues() {
        #expect(Language.enUS.rawValue == "en-US")
        #expect(Language.enGB.rawValue == "en-GB")
        #expect(Language.spanish.rawValue == "es-ES")
        #expect(Language.italian.rawValue == "it-IT")
        #expect(Language.brazilianPortuguese.rawValue == "pt-BR")
    }
}

// MARK: - Phoneme Normalizer Tests

@Suite("Phoneme Normalizer")
struct PhonemeNormalizerTests {

    @Test("Normalizer recognizes basic phonemes")
    func normalizerRecognizesBasicPhonemes() {
        let unrecognized = PhonemeNormalizer.findUnrecognizedPhonemes("a e i o u")
        #expect(unrecognized.isEmpty)
    }

    @Test("Normalizer recognizes Romance phonemes")
    func normalizerRecognizesRomancePhonemes() {
        let phonemes = "tʃ dʒ ʃ ʎ ɲ ɾ θ"
        let unrecognized = PhonemeNormalizer.findUnrecognizedPhonemes(phonemes)
        #expect(unrecognized.isEmpty)
    }

    @Test("Normalizer validates Spanish output")
    func normalizerValidatesSpanishOutput() throws {
        let processor = RomanceG2PProcessor()
        try processor.setLanguage(.spanish)

        let (phonemes, _) = try processor.process(input: "hola mundo")
        let normalized = try PhonemeNormalizer.normalize(phonemes)
        #expect(PhonemeNormalizer.isValid(normalized))
    }

    @Test("Normalizer removes length markers")
    func normalizerRemovesLengthMarkers() throws {
        let result = try PhonemeNormalizer.normalize("aː eː iː")
        #expect(!result.contains("ː"))
    }
}

// MARK: - Composite G2P Processor Tests

@Suite("Composite G2P Processor")
struct CompositeG2PProcessorTests {

    @Test("Composite processor routes Romance languages correctly")
    func compositeProcessorRoutesRomanceLanguages() throws {
        let processor = CompositeG2PProcessor()

        try processor.setLanguage(.spanish)
        let (spanishResult, _) = try processor.process(input: "hola")
        #expect(!spanishResult.isEmpty)

        try processor.setLanguage(.italian)
        let (italianResult, _) = try processor.process(input: "ciao")
        #expect(!italianResult.isEmpty)

        try processor.setLanguage(.brazilianPortuguese)
        let (portugueseResult, _) = try processor.process(input: "olá")
        #expect(!portugueseResult.isEmpty)
    }

    @Test("Composite processor normalizes Romance output")
    func compositeProcessorNormalizesRomanceOutput() throws {
        let processor = CompositeG2PProcessor()
        try processor.setLanguage(.spanish)

        let (result, _) = try processor.process(input: "español")
        // Output should be normalized to Kokoro vocabulary
        #expect(PhonemeNormalizer.isValid(result))
    }
}
