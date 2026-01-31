// KokoroVoiceExtension/SSMLParser.swift
// KokoroVoice
//
// Parses SSML (Speech Synthesis Markup Language) input and extracts
// text segments with their synthesis attributes.

import Foundation

// MARK: - SSML Parser

/// Parser for Speech Synthesis Markup Language (SSML)
/// Extracts text and synthesis parameters from SSML-formatted input
public struct SSMLParser {

    // MARK: - Synthesis Segment

    /// Represents a segment of text with its synthesis attributes
    public struct SynthesisSegment: Equatable, Sendable {
        /// The text content to synthesize
        public let text: String

        /// Speech rate multiplier (1.0 = normal, 2.0 = 2x speed)
        public let rate: Float

        /// Pitch multiplier (1.0 = normal, not fully supported by Kokoro)
        public let pitch: Float

        /// Duration of silence before this segment (in seconds)
        public let pauseBefore: Double

        public init(text: String, rate: Float, pitch: Float, pauseBefore: Double) {
            self.text = text
            self.rate = rate
            self.pitch = pitch
            self.pauseBefore = pauseBefore
        }
    }

    // MARK: - Public Methods

    /// Parse an SSML string into synthesis segments
    /// - Parameter ssml: The SSML-formatted string to parse
    /// - Returns: Array of synthesis segments with text and attributes
    public static func parse(_ ssml: String) -> [SynthesisSegment] {
        // Handle empty input
        guard !ssml.isEmpty else {
            return [SynthesisSegment(text: "", rate: 1.0, pitch: 1.0, pauseBefore: 0)]
        }

        // Check if input looks like XML
        let trimmed = ssml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<") else {
            // Plain text - return as single segment
            return [SynthesisSegment(text: ssml, rate: 1.0, pitch: 1.0, pauseBefore: 0)]
        }

        // Try XML parsing
        guard let data = ssml.data(using: .utf8) else {
            return [SynthesisSegment(text: ssml, rate: 1.0, pitch: 1.0, pauseBefore: 0)]
        }

        let xmlParser = SSMLXMLParser(data: data)
        let segments = xmlParser.parse()

        // If parsing failed or returned empty, fall back to plain text extraction
        if segments.isEmpty {
            let plainText = extractPlainText(from: ssml)
            return [SynthesisSegment(text: plainText, rate: 1.0, pitch: 1.0, pauseBefore: 0)]
        }

        return segments
    }

    // MARK: - Private Methods

    /// Extract plain text by stripping XML tags
    /// - Parameter ssml: The SSML string
    /// - Returns: Plain text with tags removed
    private static func extractPlainText(from ssml: String) -> String {
        // Simple regex-based tag removal
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ssml
        }

        let range = NSRange(ssml.startIndex..., in: ssml)
        let plainText = regex.stringByReplacingMatches(in: ssml, options: [], range: range, withTemplate: "")

        // Decode XML entities
        return decodeXMLEntities(plainText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode common XML entities
    private static func decodeXMLEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        return result
    }
}

// MARK: - XML Parser Delegate

/// Internal XML parser for SSML documents
private class SSMLXMLParser: NSObject, XMLParserDelegate {

    // MARK: - Properties

    private let parser: XMLParser
    private var segments: [SSMLParser.SynthesisSegment] = []
    private var currentText = ""
    private var pendingPause: Double = 0

    // Stacks for nested prosody elements
    private var rateStack: [Float] = [1.0]
    private var pitchStack: [Float] = [1.0]

    // Track if we're inside relevant content
    private var depth = 0

    // MARK: - Initialization

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    // MARK: - Public Methods

    func parse() -> [SSMLParser.SynthesisSegment] {
        parser.parse()

        // Add any remaining text as a segment
        flushCurrentText()

        // Filter out empty segments
        return segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Private Methods

    private func flushCurrentText() {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            currentText = ""
            return
        }

        segments.append(SSMLParser.SynthesisSegment(
            text: trimmedText,
            rate: rateStack.last ?? 1.0,
            pitch: pitchStack.last ?? 1.0,
            pauseBefore: pendingPause
        ))

        currentText = ""
        pendingPause = 0
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        depth += 1

        switch elementName.lowercased() {
        case "prosody":
            // Flush current text before prosody change
            flushCurrentText()

            // Parse and push rate
            var newRate = rateStack.last ?? 1.0
            if let rateStr = attributeDict["rate"] {
                newRate = parseRate(rateStr)
            }
            rateStack.append(newRate)

            // Parse and push pitch
            var newPitch = pitchStack.last ?? 1.0
            if let pitchStr = attributeDict["pitch"] {
                newPitch = parsePitch(pitchStr)
            }
            pitchStack.append(newPitch)

        case "break":
            // Flush current text before break
            flushCurrentText()

            // Parse break duration
            if let timeStr = attributeDict["time"] {
                pendingPause += parseTime(timeStr)
            } else if let strengthStr = attributeDict["strength"] {
                pendingPause += parseStrength(strengthStr)
            } else {
                // Default break duration
                pendingPause += 0.5
            }

        case "p":
            // Paragraph - add a longer pause
            flushCurrentText()
            pendingPause += 0.75

        case "s":
            // Sentence - add a short pause
            flushCurrentText()
            pendingPause += 0.3

        case "speak", "voice", "phoneme", "say-as", "sub", "emphasis", "mark", "desc":
            // Container elements - no special handling needed for start
            break

        default:
            // Unknown elements - continue processing content
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1

        switch elementName.lowercased() {
        case "prosody":
            // Flush current text with current prosody settings
            flushCurrentText()

            // Pop prosody stacks
            if rateStack.count > 1 { rateStack.removeLast() }
            if pitchStack.count > 1 { pitchStack.removeLast() }

        case "p":
            // End of paragraph
            flushCurrentText()

        case "s":
            // End of sentence
            flushCurrentText()

        case "speak", "voice", "phoneme", "say-as", "sub", "emphasis", "mark", "desc", "break":
            // No special end handling needed
            break

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Log but don't crash - we'll fall back to plain text extraction
        print("SSMLParser: XML parse error: \(parseError.localizedDescription)")
    }

    // MARK: - Attribute Parsing

    /// Parse rate attribute value
    /// Supports: percentage (150%, +50%, -25%), named values (slow, fast, etc.)
    private func parseRate(_ value: String) -> Float {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()

        // Percentage values
        if trimmed.hasSuffix("%") {
            let numStr = String(trimmed.dropLast())

            if numStr.hasPrefix("+") {
                // Positive offset: "+50%" = 1.5
                if let percent = Float(String(numStr.dropFirst())) {
                    return 1.0 + (percent / 100.0)
                }
            } else if numStr.hasPrefix("-") {
                // Negative offset: "-25%" = 0.75
                if let percent = Float(String(numStr.dropFirst())) {
                    return 1.0 - (percent / 100.0)
                }
            } else {
                // Absolute percentage: "150%" = 1.5
                if let percent = Float(numStr) {
                    return percent / 100.0
                }
            }
        }

        // Named values
        switch trimmed {
        case "x-slow": return 0.5
        case "slow": return 0.75
        case "medium", "default": return 1.0
        case "fast": return 1.25
        case "x-fast": return 1.5
        default: return 1.0
        }
    }

    /// Parse pitch attribute value
    /// Note: Kokoro has limited pitch control
    private func parsePitch(_ value: String) -> Float {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()

        // Percentage values
        if trimmed.hasSuffix("%") {
            let numStr = String(trimmed.dropLast())
            if let percent = Float(numStr) {
                return percent / 100.0
            }
        }

        // Semitone values (e.g., "+2st", "-3st")
        if trimmed.hasSuffix("st") {
            let numStr = String(trimmed.dropLast(2))
            if let semitones = Float(numStr) {
                // Convert semitones to multiplier (12 semitones = 1 octave = 2x)
                return pow(2.0, semitones / 12.0)
            }
        }

        // Hertz values
        if trimmed.hasSuffix("hz") {
            // Ignore Hz values for now - would need base frequency
            return 1.0
        }

        // Named values
        switch trimmed {
        case "x-low": return 0.5
        case "low": return 0.75
        case "medium", "default": return 1.0
        case "high": return 1.25
        case "x-high": return 1.5
        default: return 1.0
        }
    }

    /// Parse time duration attribute
    /// Supports: seconds (1s, 0.5s), milliseconds (500ms)
    private func parseTime(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()

        if trimmed.hasSuffix("ms") {
            // Milliseconds
            let numStr = String(trimmed.dropLast(2))
            if let ms = Double(numStr) {
                return ms / 1000.0
            }
        } else if trimmed.hasSuffix("s") {
            // Seconds
            let numStr = String(trimmed.dropLast())
            if let seconds = Double(numStr) {
                return seconds
            }
        }

        // Try parsing as plain number (assume seconds)
        if let seconds = Double(trimmed) {
            return seconds
        }

        // Default
        return 0.5
    }

    /// Parse break strength attribute
    /// Maps named strengths to pause durations
    private func parseStrength(_ value: String) -> Double {
        switch value.lowercased() {
        case "none": return 0.0
        case "x-weak": return 0.1
        case "weak": return 0.25
        case "medium": return 0.5
        case "strong": return 0.75
        case "x-strong": return 1.0
        default: return 0.5
        }
    }
}
