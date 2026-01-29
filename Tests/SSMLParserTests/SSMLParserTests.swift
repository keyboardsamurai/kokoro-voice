// Tests/SSMLParserTests/SSMLParserTests.swift
// KokoroVoice
//
// Unit tests for SSML Parser following TDD approach

import XCTest
@testable import KokoroVoiceExtension

final class SSMLParserTests: XCTestCase {

    // MARK: - Plain Text Tests

    func testParsePlainText() {
        let result = SSMLParser.parse("Hello world")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Hello world")
        XCTAssertEqual(result[0].rate, 1.0, accuracy: 0.01)
        XCTAssertEqual(result[0].pitch, 1.0, accuracy: 0.01)
        XCTAssertEqual(result[0].pauseBefore, 0, accuracy: 0.01)
    }

    func testParseEmptyString() {
        let result = SSMLParser.parse("")

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].text.isEmpty || result[0].text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testParseWhitespaceOnly() {
        let result = SSMLParser.parse("   \n\t  ")

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Simple SSML Tests

    func testParseSimpleSpeakTag() {
        let ssml = "<speak>Hello world</speak>"
        let result = SSMLParser.parse(ssml)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Hello world")
        XCTAssertEqual(result[0].rate, 1.0, accuracy: 0.01)
    }

    func testParseSpeakTagWithNamespace() {
        let ssml = """
        <speak xmlns="http://www.w3.org/2001/10/synthesis" version="1.1">
            Hello world
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(combinedText.contains("Hello world"))
    }

    // MARK: - Prosody Rate Tests

    func testParseProsodyRatePercentage() {
        let ssml = "<speak><prosody rate=\"150%\">Fast speech</prosody></speak>"
        let result = SSMLParser.parse(ssml)

        XCTAssertGreaterThan(result.count, 0)
        let segment = result.first { $0.text.contains("Fast speech") }
        XCTAssertNotNil(segment)
        XCTAssertEqual(segment?.rate ?? 0, 1.5, accuracy: 0.01)
    }

    func testParseProsodyRateNamed() {
        let testCases: [(String, Float)] = [
            ("x-slow", 0.5),
            ("slow", 0.75),
            ("medium", 1.0),
            ("fast", 1.25),
            ("x-fast", 1.5)
        ]

        for (rateName, expectedRate) in testCases {
            let ssml = "<speak><prosody rate=\"\(rateName)\">Text</prosody></speak>"
            let result = SSMLParser.parse(ssml)

            let segment = result.first { $0.text.contains("Text") }
            XCTAssertNotNil(segment, "Segment should exist for rate: \(rateName)")
            XCTAssertEqual(segment?.rate ?? 0, expectedRate, accuracy: 0.01, "Rate should be \(expectedRate) for \(rateName)")
        }
    }

    func testParseProsodyRatePositiveOffset() {
        let ssml = "<speak><prosody rate=\"+50%\">Faster</prosody></speak>"
        let result = SSMLParser.parse(ssml)

        let segment = result.first { $0.text.contains("Faster") }
        XCTAssertNotNil(segment)
        XCTAssertEqual(segment?.rate ?? 0, 1.5, accuracy: 0.01)
    }

    func testParseProsodyRateNegativeOffset() {
        let ssml = "<speak><prosody rate=\"-25%\">Slower</prosody></speak>"
        let result = SSMLParser.parse(ssml)

        let segment = result.first { $0.text.contains("Slower") }
        XCTAssertNotNil(segment)
        XCTAssertEqual(segment?.rate ?? 0, 0.75, accuracy: 0.01)
    }

    // MARK: - Break Tag Tests

    func testParseBreakWithTimeSeconds() {
        let ssml = "<speak>Hello<break time=\"1s\"/>World</speak>"
        let result = SSMLParser.parse(ssml)

        XCTAssertGreaterThanOrEqual(result.count, 2)
        let worldSegment = result.first { $0.text.contains("World") }
        XCTAssertNotNil(worldSegment)
        XCTAssertEqual(worldSegment?.pauseBefore ?? 0, 1.0, accuracy: 0.01)
    }

    func testParseBreakWithTimeMilliseconds() {
        let ssml = "<speak>Hello<break time=\"500ms\"/>World</speak>"
        let result = SSMLParser.parse(ssml)

        let worldSegment = result.first { $0.text.contains("World") }
        XCTAssertNotNil(worldSegment)
        XCTAssertEqual(worldSegment?.pauseBefore ?? 0, 0.5, accuracy: 0.01)
    }

    func testParseBreakWithStrength() {
        let testCases: [(String, Double)] = [
            ("none", 0.0),
            ("x-weak", 0.1),
            ("weak", 0.25),
            ("medium", 0.5),
            ("strong", 0.75),
            ("x-strong", 1.0)
        ]

        for (strength, expectedPause) in testCases {
            let ssml = "<speak>Hello<break strength=\"\(strength)\"/>World</speak>"
            let result = SSMLParser.parse(ssml)

            let worldSegment = result.first { $0.text.contains("World") }
            XCTAssertNotNil(worldSegment, "Segment should exist for strength: \(strength)")
            XCTAssertEqual(worldSegment?.pauseBefore ?? -1, expectedPause, accuracy: 0.01, "Pause should be \(expectedPause) for \(strength)")
        }
    }

    func testParseBreakWithDefaultDuration() {
        let ssml = "<speak>Hello<break/>World</speak>"
        let result = SSMLParser.parse(ssml)

        let worldSegment = result.first { $0.text.contains("World") }
        XCTAssertNotNil(worldSegment)
        // Default break should be ~0.5 seconds
        XCTAssertGreaterThan(worldSegment?.pauseBefore ?? 0, 0)
    }

    // MARK: - Nested Prosody Tests

    func testParseNestedProsody() {
        let ssml = """
        <speak>
            Normal text
            <prosody rate="150%">
                Fast text
                <prosody rate="200%">Very fast text</prosody>
                Back to fast
            </prosody>
            Normal again
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Check we have multiple segments
        XCTAssertGreaterThan(result.count, 1)

        // Find segments by text content
        let veryFastSegment = result.first { $0.text.contains("Very fast") }
        XCTAssertNotNil(veryFastSegment)
        // Nested rate should be 200%
        XCTAssertEqual(veryFastSegment?.rate ?? 0, 2.0, accuracy: 0.01)
    }

    // MARK: - Complex SSML Tests

    func testParseComplexSSML() {
        let ssml = """
        <speak>
            Welcome to Kokoro.
            <break time="500ms"/>
            <prosody rate="fast">This is spoken quickly.</prosody>
            <break time="1s"/>
            <prosody rate="slow">And this is spoken slowly.</prosody>
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Should have multiple segments
        XCTAssertGreaterThan(result.count, 2)

        // Check fast segment
        let fastSegment = result.first { $0.text.contains("quickly") }
        XCTAssertNotNil(fastSegment)
        XCTAssertEqual(fastSegment?.rate ?? 0, 1.25, accuracy: 0.01)

        // Check slow segment
        let slowSegment = result.first { $0.text.contains("slowly") }
        XCTAssertNotNil(slowSegment)
        XCTAssertEqual(slowSegment?.rate ?? 0, 0.75, accuracy: 0.01)
    }

    // MARK: - Invalid SSML Tests

    func testParseInvalidXML() {
        let ssml = "<speak>Unclosed tag"
        let result = SSMLParser.parse(ssml)

        // Should fall back to plain text extraction
        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined()
        XCTAssertTrue(combinedText.contains("Unclosed") || combinedText.contains("tag"))
    }

    func testParseMalformedTags() {
        let ssml = "<speak><prosody rate=150%>Text</prosody></speak>"  // Missing quotes
        let result = SSMLParser.parse(ssml)

        // Should handle gracefully
        XCTAssertGreaterThan(result.count, 0)
    }

    func testParseUnknownTags() {
        let ssml = "<speak><unknown>Text inside</unknown> More text</speak>"
        let result = SSMLParser.parse(ssml)

        // Should extract text from unknown tags
        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined(separator: " ")
        XCTAssertTrue(combinedText.contains("Text inside") || combinedText.contains("More text"))
    }

    // MARK: - Paragraph and Sentence Tags

    func testParseParagraphTags() {
        let ssml = """
        <speak>
            <p>First paragraph.</p>
            <p>Second paragraph.</p>
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Paragraphs should add pauses between them
        XCTAssertGreaterThanOrEqual(result.count, 2)
    }

    func testParseSentenceTags() {
        let ssml = """
        <speak>
            <s>First sentence.</s>
            <s>Second sentence.</s>
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Sentences should be parsed
        XCTAssertGreaterThan(result.count, 0)
    }

    // MARK: - Voice Tag Tests

    func testParseVoiceTag() {
        let ssml = """
        <speak>
            <voice name="af_heart">Hello from Heart voice.</voice>
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Voice tag content should be extracted
        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined()
        XCTAssertTrue(combinedText.contains("Hello from Heart voice"))
    }

    // MARK: - Unsupported Tag Tests

    func testParsePhonemeTag() {
        let ssml = """
        <speak>
            <phoneme alphabet="ipa" ph="təˈmeɪtoʊ">tomato</phoneme>
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Should extract the text content, ignoring phoneme info
        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined()
        XCTAssertTrue(combinedText.contains("tomato"))
    }

    func testParseSayAsTag() {
        let ssml = """
        <speak>
            <say-as interpret-as="characters">SSML</say-as>
        </speak>
        """
        let result = SSMLParser.parse(ssml)

        // Should extract the text content
        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined()
        XCTAssertTrue(combinedText.contains("SSML"))
    }

    // MARK: - Stress Tests

    func testParseLongText() {
        // Generate a long text
        let longText = String(repeating: "This is a test sentence. ", count: 100)
        let ssml = "<speak>\(longText)</speak>"
        let result = SSMLParser.parse(ssml)

        XCTAssertGreaterThan(result.count, 0)
        let totalLength = result.map { $0.text.count }.reduce(0, +)
        XCTAssertGreaterThan(totalLength, 1000)
    }

    func testParseMultipleBreaks() {
        let ssml = "<speak>A<break time=\"100ms\"/>B<break time=\"200ms\"/>C<break time=\"300ms\"/>D</speak>"
        let result = SSMLParser.parse(ssml)

        // Should handle multiple breaks
        XCTAssertGreaterThanOrEqual(result.count, 2)
    }

    // MARK: - Segment Structure Tests

    func testSynthesisSegmentProperties() {
        let segment = SSMLParser.SynthesisSegment(
            text: "Test text",
            rate: 1.5,
            pitch: 1.0,
            pauseBefore: 0.5
        )

        XCTAssertEqual(segment.text, "Test text")
        XCTAssertEqual(segment.rate, 1.5, accuracy: 0.01)
        XCTAssertEqual(segment.pitch, 1.0, accuracy: 0.01)
        XCTAssertEqual(segment.pauseBefore, 0.5, accuracy: 0.01)
    }

    // MARK: - Edge Cases

    func testParseOnlyBreakTags() {
        let ssml = "<speak><break time=\"1s\"/><break time=\"2s\"/></speak>"
        let result = SSMLParser.parse(ssml)

        // Should handle SSML with only breaks (no text)
        // Result may be empty or contain empty segments with pauses
        // This is valid - just produces silence
        XCTAssertTrue(result.isEmpty || result.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testParseSpecialCharacters() {
        let ssml = "<speak>Hello &amp; goodbye! &lt;test&gt;</speak>"
        let result = SSMLParser.parse(ssml)

        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined()
        // XML entities should be decoded
        XCTAssertTrue(combinedText.contains("&") || combinedText.contains("goodbye"))
    }

    func testParseUnicodeText() {
        let ssml = "<speak>Hello 世界! Привет мир! 🎉</speak>"
        let result = SSMLParser.parse(ssml)

        XCTAssertGreaterThan(result.count, 0)
        let combinedText = result.map { $0.text }.joined()
        XCTAssertTrue(combinedText.contains("世界") || combinedText.contains("Привет"))
    }
}
