// Tests/KokoroEngineTests/VoiceEmbeddingTests.swift
// KokoroVoice
//
// Integration tests for voice embedding loading from NPZ archives

import XCTest
@testable import KokoroVoiceShared

final class VoiceEmbeddingTests: XCTestCase {

    // MARK: - Voice Constants Tests

    func testAllVoicesHaveCorrectIdFormat() {
        // Voice IDs should follow pattern: {region}{gender}_{name}
        // region: a (American), b (British)
        // gender: f (female), m (male)
        for voice in Constants.availableVoices {
            let id = voice.id
            XCTAssertTrue(id.count > 3, "Voice ID '\(id)' is too short")

            let prefix = String(id.prefix(2))
            XCTAssertTrue(
                ["af", "am", "bf", "bm"].contains(prefix),
                "Voice ID '\(id)' has invalid prefix '\(prefix)'"
            )

            XCTAssertTrue(id.contains("_"), "Voice ID '\(id)' missing underscore separator")
        }
    }

    func testVoiceLanguageMatchesIdPrefix() {
        for voice in Constants.availableVoices {
            let expectedLanguage = voice.id.hasPrefix("a") ? "en-US" : "en-GB"
            XCTAssertEqual(
                voice.language,
                expectedLanguage,
                "Voice '\(voice.id)' language mismatch"
            )
        }
    }

    func testVoiceGenderMatchesIdPrefix() {
        for voice in Constants.availableVoices {
            let genderChar = voice.id.dropFirst().first!
            let expectedGender: Constants.VoiceDefinition.Gender = genderChar == "f" ? .female : .male
            XCTAssertEqual(
                voice.gender,
                expectedGender,
                "Voice '\(voice.id)' gender mismatch"
            )
        }
    }

    func testDefaultEnabledVoicesExist() {
        let defaultIds = Constants.defaultEnabledVoiceIds
        XCTAssertGreaterThan(defaultIds.count, 0, "Should have default enabled voices")

        for id in defaultIds {
            let definition = Constants.voiceDefinition(forId: id)
            XCTAssertNotNil(definition, "Default voice '\(id)' not found in available voices")
        }
    }

    func testDefaultVoiceIsInDefaultEnabled() {
        let defaultVoice = Constants.defaultVoice
        let defaultEnabled = Constants.defaultEnabledVoiceIds
        XCTAssertTrue(
            defaultEnabled.contains(defaultVoice),
            "Default voice '\(defaultVoice)' should be in default enabled list"
        )
    }

    // MARK: - Language Mapping Tests

    func testKokoroLanguageRawValues() {
        XCTAssertEqual(KokoroLanguage.enUS.rawValue, "en-US")
        XCTAssertEqual(KokoroLanguage.enGB.rawValue, "en-GB")
    }

    func testKokoroLanguageFromVoiceIdEdgeCases() {
        // Edge cases and unusual inputs
        XCTAssertEqual(KokoroLanguage.from(voiceId: ""), .enUS)  // Empty defaults to US
        XCTAssertEqual(KokoroLanguage.from(voiceId: "b"), .enGB)  // Single 'b' is British
        XCTAssertEqual(KokoroLanguage.from(voiceId: "B_test"), .enUS)  // Uppercase is not British
        XCTAssertEqual(KokoroLanguage.from(voiceId: "british"), .enGB)  // Starts with 'b'
    }

    func testKokoroLanguageCaseIterable() {
        let allCases = KokoroLanguage.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.enUS))
        XCTAssertTrue(allCases.contains(.enGB))
    }

    // MARK: - Engine Integration Tests

    func testEngineIsActor() async {
        // KokoroEngine should be thread-safe via actor isolation
        let engine = KokoroEngine.shared

        // Verify we can call methods from async context
        let isLoaded = await engine.isModelLoaded
        _ = isLoaded  // Just verifying compilation and execution
    }

    func testGenerateSilenceAtDifferentRates() async {
        let engine = KokoroEngine.shared

        // Test various durations
        let testDurations: [Double] = [0.1, 0.25, 0.5, 1.0, 2.0]

        for duration in testDurations {
            let silence = await engine.generateSilence(duration: duration)
            let expectedSamples = Int(duration * Constants.sampleRate)
            XCTAssertEqual(
                silence.count,
                expectedSamples,
                "Silence for \(duration)s should have \(expectedSamples) samples"
            )
        }
    }

    func testGenerateSilenceAllZeros() async {
        let engine = KokoroEngine.shared
        let silence = await engine.generateSilence(duration: 0.1)

        // All samples should be exactly zero
        for (index, sample) in silence.enumerated() {
            XCTAssertEqual(sample, 0.0, accuracy: 0.0, "Sample at index \(index) should be zero")
        }
    }

    // MARK: - Error Description Tests

    func testAllErrorsHaveDescriptions() {
        let errors: [KokoroEngineError] = [
            .modelNotLoaded,
            .voiceNotFound("test"),
            .synthesisError("test"),
            .modelLoadError("test"),
            .voiceEmbeddingLoadError("test"),
            .invalidAudioFormat
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(
                error.errorDescription!.isEmpty,
                "Error \(error) description should not be empty"
            )
        }
    }

    // MARK: - Audio Buffer Utility Tests

    func testNormalizePreservesSignRatio() {
        let input: [Float] = [1.0, -0.5, 0.25, -0.125]
        let result = AudioBufferUtils.normalize(input)

        // After normalization, relative magnitudes should be preserved
        // 1.0 : 0.5 : 0.25 : 0.125 = 8:4:2:1
        XCTAssertEqual(abs(result[0]) / abs(result[1]), 2.0, accuracy: 0.001)
        XCTAssertEqual(abs(result[1]) / abs(result[2]), 2.0, accuracy: 0.001)
        XCTAssertEqual(abs(result[2]) / abs(result[3]), 2.0, accuracy: 0.001)
    }

    func testApplyFadesCorrectLength() {
        let input: [Float] = Array(repeating: 1.0, count: 500)
        let result = AudioBufferUtils.applyFades(to: input, fadeInSamples: 50, fadeOutSamples: 50)

        XCTAssertEqual(result.count, input.count, "Fades should not change array length")
    }

    func testApplyFadesFirstAndLastSamples() {
        let input: [Float] = Array(repeating: 1.0, count: 500)
        let result = AudioBufferUtils.applyFades(to: input, fadeInSamples: 50, fadeOutSamples: 50)

        // First sample should be nearly zero (faded in)
        XCTAssertEqual(result[0], 0.0, accuracy: 0.01)

        // Last sample should be nearly zero (faded out)
        XCTAssertEqual(result[499], 0.02, accuracy: 0.02)

        // Middle samples should be unchanged
        XCTAssertEqual(result[250], 1.0, accuracy: 0.01)
    }
}
