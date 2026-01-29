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
}
