// Tests/VoiceConfigurationTests/VoiceConfigurationTests.swift
// KokoroVoice
//
// Unit tests for VoiceConfiguration following TDD approach

import XCTest
@testable import KokoroVoiceShared

final class VoiceConfigurationTests: XCTestCase {

    // MARK: - VoiceConfiguration Model Tests

    func testVoiceConfigurationInitialization() {
        let config = VoiceConfiguration(
            id: "af_heart",
            name: "Kokoro Heart",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: true
        )

        XCTAssertEqual(config.id, "af_heart")
        XCTAssertEqual(config.name, "Kokoro Heart")
        XCTAssertEqual(config.language, "en-US")
        XCTAssertEqual(config.gender, .female)
        XCTAssertEqual(config.quality, .a)
        XCTAssertTrue(config.isEnabled)
    }

    func testVoiceConfigurationIdentifier() {
        let config = VoiceConfiguration(
            id: "af_heart",
            name: "Kokoro Heart",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: true
        )

        XCTAssertEqual(config.identifier, "com.kokorovoice.af_heart")
    }

    func testVoiceConfigurationDisplayName() {
        let femaleConfig = VoiceConfiguration(
            id: "af_heart",
            name: "Kokoro Heart",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: true
        )
        XCTAssertEqual(femaleConfig.displayName, "Kokoro Heart (Female)")

        let maleConfig = VoiceConfiguration(
            id: "am_adam",
            name: "Kokoro Adam",
            language: "en-US",
            gender: .male,
            quality: .a,
            isEnabled: true
        )
        XCTAssertEqual(maleConfig.displayName, "Kokoro Adam (Male)")
    }

    func testVoiceConfigurationCodable() throws {
        let original = VoiceConfiguration(
            id: "af_bella",
            name: "Kokoro Bella",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VoiceConfiguration.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.language, original.language)
        XCTAssertEqual(decoded.gender, original.gender)
        XCTAssertEqual(decoded.quality, original.quality)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
    }

    func testVoiceConfigurationFromDefinition() {
        guard let definition = Constants.voiceDefinition(forId: "af_heart") else {
            XCTFail("Voice definition not found")
            return
        }

        let config = VoiceConfiguration(from: definition, isEnabled: true)

        XCTAssertEqual(config.id, definition.id)
        XCTAssertEqual(config.name, definition.name)
        XCTAssertEqual(config.language, definition.language)
        XCTAssertTrue(config.isEnabled)
    }

    // MARK: - VoiceConfigurationManager Tests

    func testManagerReturnsDefaultVoicesOnFirstLaunch() {
        // Create a test manager with a unique suite name
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)

        // Clear any existing data
        manager.clearAll()

        let enabledVoices = manager.getEnabledVoices()

        // Should return default enabled voices
        XCTAssertFalse(enabledVoices.isEmpty)

        // Clean up
        manager.clearAll()
    }

    func testManagerSavesAndLoadsVoices() {
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)
        manager.clearAll()

        let testVoices = [
            VoiceConfiguration(
                id: "af_heart",
                name: "Kokoro Heart",
                language: "en-US",
                gender: .female,
                quality: .a,
                isEnabled: true
            ),
            VoiceConfiguration(
                id: "am_adam",
                name: "Kokoro Adam",
                language: "en-US",
                gender: .male,
                quality: .a,
                isEnabled: false
            )
        ]

        manager.saveVoiceConfigurations(testVoices)
        let loaded = manager.getAllVoices()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, "af_heart")
        XCTAssertTrue(loaded[0].isEnabled)
        XCTAssertEqual(loaded[1].id, "am_adam")
        XCTAssertFalse(loaded[1].isEnabled)

        manager.clearAll()
    }

    func testManagerGetEnabledVoicesFiltersCorrectly() {
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)
        manager.clearAll()

        let testVoices = [
            VoiceConfiguration(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a, isEnabled: true),
            VoiceConfiguration(id: "am_adam", name: "Adam", language: "en-US", gender: .male, quality: .a, isEnabled: false),
            VoiceConfiguration(id: "bf_alice", name: "Alice", language: "en-GB", gender: .female, quality: .a, isEnabled: true)
        ]

        manager.saveVoiceConfigurations(testVoices)
        let enabledVoices = manager.getEnabledVoices()

        XCTAssertEqual(enabledVoices.count, 2)
        XCTAssertTrue(enabledVoices.allSatisfy { $0.isEnabled })
        XCTAssertTrue(enabledVoices.contains { $0.id == "af_heart" })
        XCTAssertTrue(enabledVoices.contains { $0.id == "bf_alice" })
        XCTAssertFalse(enabledVoices.contains { $0.id == "am_adam" })

        manager.clearAll()
    }

    func testManagerToggleVoice() {
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)
        manager.clearAll()

        let testVoices = [
            VoiceConfiguration(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a, isEnabled: true)
        ]

        manager.saveVoiceConfigurations(testVoices)

        // Toggle off
        manager.toggleVoice(withId: "af_heart")
        var loaded = manager.getAllVoices()
        XCTAssertFalse(loaded[0].isEnabled)

        // Toggle on
        manager.toggleVoice(withId: "af_heart")
        loaded = manager.getAllVoices()
        XCTAssertTrue(loaded[0].isEnabled)

        manager.clearAll()
    }

    func testManagerSetVoiceEnabled() {
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)
        manager.clearAll()

        let testVoices = [
            VoiceConfiguration(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a, isEnabled: false)
        ]

        manager.saveVoiceConfigurations(testVoices)

        manager.setVoiceEnabled(withId: "af_heart", enabled: true)
        var loaded = manager.getAllVoices()
        XCTAssertTrue(loaded[0].isEnabled)

        manager.setVoiceEnabled(withId: "af_heart", enabled: false)
        loaded = manager.getAllVoices()
        XCTAssertFalse(loaded[0].isEnabled)

        manager.clearAll()
    }

    // MARK: - Edge Cases

    func testVoiceConfigurationWithEmptyName() {
        let config = VoiceConfiguration(
            id: "test_voice",
            name: "",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: true
        )

        // Should still have valid identifier
        XCTAssertEqual(config.identifier, "com.kokorovoice.test_voice")
        // Display name should handle empty name
        XCTAssertEqual(config.displayName, " (Female)")
    }

    func testManagerHandlesNonExistentVoiceToggle() {
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)
        manager.clearAll()

        let testVoices = [
            VoiceConfiguration(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a, isEnabled: true)
        ]

        manager.saveVoiceConfigurations(testVoices)

        // Should not crash when toggling non-existent voice
        manager.toggleVoice(withId: "nonexistent_voice")

        let loaded = manager.getAllVoices()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded[0].isEnabled) // Original voice unchanged

        manager.clearAll()
    }

    func testManagerReturnsVoiceById() {
        let testSuiteName = "test.voiceconfig.\(UUID().uuidString)"
        let manager = VoiceConfigurationManager(suiteName: testSuiteName)
        manager.clearAll()

        let testVoices = [
            VoiceConfiguration(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a, isEnabled: true),
            VoiceConfiguration(id: "am_adam", name: "Adam", language: "en-US", gender: .male, quality: .a, isEnabled: false)
        ]

        manager.saveVoiceConfigurations(testVoices)

        let voice = manager.getVoice(byId: "af_heart")
        XCTAssertNotNil(voice)
        XCTAssertEqual(voice?.id, "af_heart")

        let nonExistent = manager.getVoice(byId: "nonexistent")
        XCTAssertNil(nonExistent)

        manager.clearAll()
    }

    // MARK: - Multi-Language Support Tests

    func testSupportedLanguageDefaultVoices() {
        XCTAssertEqual(SupportedLanguage.americanEnglish.defaultVoiceId, "af_heart")
        XCTAssertEqual(SupportedLanguage.britishEnglish.defaultVoiceId, "bf_emma")
        XCTAssertEqual(SupportedLanguage.spanish.defaultVoiceId, "ef_dora")
        XCTAssertEqual(SupportedLanguage.italian.defaultVoiceId, "if_sara")
        XCTAssertEqual(SupportedLanguage.brazilianPortuguese.defaultVoiceId, "pf_dora")
    }

    func testSupportedLanguageMatchExact() {
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en-US"), .americanEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en-GB"), .britishEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "es-ES"), .spanish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "it-IT"), .italian)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "pt-BR"), .brazilianPortuguese)
    }

    func testSupportedLanguageMatchFallback() {
        // Spanish variants should fall back to es-ES
        XCTAssertEqual(SupportedLanguage.match(bcp47: "es-MX"), .spanish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "es-AR"), .spanish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "es"), .spanish)

        // Portuguese variants should fall back to pt-BR
        XCTAssertEqual(SupportedLanguage.match(bcp47: "pt-PT"), .brazilianPortuguese)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "pt"), .brazilianPortuguese)

        // English variants should fall back to en-US
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en-AU"), .americanEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en-CA"), .americanEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en"), .americanEnglish)
    }

    func testSupportedLanguageMatchCaseInsensitive() {
        // Lowercase variants
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en-us"), .americanEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en-gb"), .britishEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "es-es"), .spanish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "it-it"), .italian)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "pt-br"), .brazilianPortuguese)

        // Underscore variants (locale format)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en_US"), .americanEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "en_gb"), .britishEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "es_ES"), .spanish)

        // Mixed case
        XCTAssertEqual(SupportedLanguage.match(bcp47: "EN-us"), .americanEnglish)
        XCTAssertEqual(SupportedLanguage.match(bcp47: "Es-eS"), .spanish)
    }

    func testSupportedLanguageMatchUnsupported() {
        // Unsupported languages should return nil
        XCTAssertNil(SupportedLanguage.match(bcp47: "ja-JP"))
        XCTAssertNil(SupportedLanguage.match(bcp47: "zh-CN"))
        XCTAssertNil(SupportedLanguage.match(bcp47: "fr-FR"))
        XCTAssertNil(SupportedLanguage.match(bcp47: "de-DE"))
    }

    // MARK: - Voice Definition Tests

    func testAllVoiceDefinitionsAre36() {
        XCTAssertEqual(Constants.availableVoices.count, 36)
    }

    func testVoiceDefinitionsHaveUniqueIds() {
        let ids = Constants.availableVoices.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Duplicate voice IDs found")
    }

    func testEnglishVoiceCount() {
        let enUSVoices = Constants.availableVoices.filter { $0.language == "en-US" }
        let enGBVoices = Constants.availableVoices.filter { $0.language == "en-GB" }

        XCTAssertEqual(enUSVoices.count, 20, "Expected 20 en-US voices")
        XCTAssertEqual(enGBVoices.count, 8, "Expected 8 en-GB voices")
    }

    func testRomanceVoiceCount() {
        let spanishVoices = Constants.availableVoices.filter { $0.language == "es-ES" }
        let italianVoices = Constants.availableVoices.filter { $0.language == "it-IT" }
        let portugueseVoices = Constants.availableVoices.filter { $0.language == "pt-BR" }

        XCTAssertEqual(spanishVoices.count, 3, "Expected 3 Spanish voices")
        XCTAssertEqual(italianVoices.count, 2, "Expected 2 Italian voices")
        XCTAssertEqual(portugueseVoices.count, 3, "Expected 3 Portuguese voices")
    }

    func testDefaultEnabledVoicesAreOnePerLanguage() {
        let defaultIds = Constants.defaultEnabledVoiceIds
        XCTAssertEqual(defaultIds.count, 5, "Expected 5 default voices (one per language)")

        // Verify each language has exactly one default
        for language in SupportedLanguage.allCases {
            let defaultForLanguage = defaultIds.filter { voiceId in
                Constants.voiceDefinition(forId: voiceId)?.language == language.rawValue
            }
            XCTAssertEqual(defaultForLanguage.count, 1, "Expected exactly 1 default for \(language.rawValue)")
        }
    }

    func testVoiceConfigurationLanguageChecks() {
        // Spanish voice
        let spanishConfig = VoiceConfiguration(
            id: "ef_dora",
            name: "Dora",
            language: "es-ES",
            gender: .female,
            quality: .b,
            isEnabled: true
        )
        XCTAssertTrue(spanishConfig.isSpanish)
        XCTAssertTrue(spanishConfig.isRomanceLanguage)
        XCTAssertFalse(spanishConfig.isAmericanEnglish)
        XCTAssertFalse(spanishConfig.isBritishEnglish)

        // Italian voice
        let italianConfig = VoiceConfiguration(
            id: "if_sara",
            name: "Sara",
            language: "it-IT",
            gender: .female,
            quality: .b,
            isEnabled: true
        )
        XCTAssertTrue(italianConfig.isItalian)
        XCTAssertTrue(italianConfig.isRomanceLanguage)

        // Portuguese voice
        let portugueseConfig = VoiceConfiguration(
            id: "pf_dora",
            name: "Dora",
            language: "pt-BR",
            gender: .female,
            quality: .b,
            isEnabled: true
        )
        XCTAssertTrue(portugueseConfig.isBrazilianPortuguese)
        XCTAssertTrue(portugueseConfig.isRomanceLanguage)

        // English voice should not be Romance
        let englishConfig = VoiceConfiguration(
            id: "af_heart",
            name: "Heart",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: true
        )
        XCTAssertFalse(englishConfig.isRomanceLanguage)
        XCTAssertTrue(englishConfig.isAmericanEnglish)
    }

    func testVoiceConfigurationKokoroLanguageCode() {
        let spanishConfig = VoiceConfiguration(
            id: "ef_dora",
            name: "Dora",
            language: "es-ES",
            gender: .female,
            quality: .b,
            isEnabled: true
        )
        XCTAssertEqual(spanishConfig.kokoroLanguageCode, "es-ES")

        let englishConfig = VoiceConfiguration(
            id: "af_heart",
            name: "Heart",
            language: "en-US",
            gender: .female,
            quality: .a,
            isEnabled: true
        )
        XCTAssertEqual(englishConfig.kokoroLanguageCode, "en-US")
    }
}
