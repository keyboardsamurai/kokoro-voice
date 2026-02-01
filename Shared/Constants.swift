// Shared/Constants.swift
// KokoroVoice
//
// Shared constants used by both the host app and the extension.

import Foundation

// MARK: - Supported Languages

/// Supported languages with their BCP-47 codes
public enum SupportedLanguage: String, CaseIterable, Sendable {
    case americanEnglish = "en-US"
    case britishEnglish = "en-GB"
    case spanish = "es-ES"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"

    /// Default voice ID for each language
    public var defaultVoiceId: String {
        switch self {
        case .americanEnglish: return "af_heart"
        case .britishEnglish: return "bf_emma"
        case .spanish: return "ef_dora"
        case .italian: return "if_sara"
        case .brazilianPortuguese: return "pf_dora"
        }
    }

    /// Match BCP-47 language code to supported language
    /// Handles variants like es-MX → es-ES, pt-PT → pt-BR
    /// Normalizes case before matching (handles "en-gb", "en-GB", "en_GB" variants)
    public static func match(bcp47 code: String) -> SupportedLanguage? {
        // Normalize: replace underscores with hyphens, then format as "xx-XX"
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-")

        let normalizedCode: String
        if parts.count >= 2 {
            // Format as lowercase-UPPERCASE (e.g., "en-US", "es-ES")
            normalizedCode = "\(parts[0].lowercased())-\(parts[1].uppercased())"
        } else if parts.count == 1 {
            normalizedCode = parts[0].lowercased()
        } else {
            normalizedCode = code
        }

        // Exact match first (after normalization)
        if let exact = SupportedLanguage(rawValue: normalizedCode) {
            return exact
        }

        // Base language fallback
        let base = parts.first.map { String($0).lowercased() } ?? normalizedCode
        switch base {
        case "en": return .americanEnglish  // en-AU, en-CA, etc.
        case "es": return .spanish          // es-MX, es-AR, etc.
        case "it": return .italian
        case "pt": return .brazilianPortuguese  // pt-PT → pt-BR
        default: return nil
        }
    }
}

// MARK: - Constants

/// Central configuration constants for the Kokoro Voice application
public enum Constants {
    /// App Group identifier for sharing data between host app and extension
    public static let appGroupIdentifier = "group.com.kokorovoice.shared"

    /// UserDefaults key for storing enabled voices
    public static let voicesKey = "enabledVoices"

    /// Default voice to use when none specified
    public static let defaultVoice = "af_heart"

    /// Audio sample rate for Kokoro TTS output (24 kHz)
    public static let sampleRate: Double = 24000

    /// Number of audio channels (mono)
    public static let channelCount: UInt32 = 1

    /// Voice identifier prefix for system registration
    /// Full identifier format: com.kokorovoice.{voiceName}
    public static let voiceIdentifierPrefix = "com.kokorovoice."

    /// Audio Unit component description
    public enum AudioUnit {
        /// Manufacturer code (4 characters) - "KOKO"
        public static let manufacturer: String = "KOKO"

        /// Subtype code (4 characters)
        public static let subtype: String = "KVSP"

        /// Type code for speech synthesizer
        public static let type: String = "ausp"
    }

    /// Voice definition with ID, display name, and language
    public struct VoiceDefinition: Sendable {
        public let id: String
        public let name: String
        public let language: String
        public let gender: Gender
        public let quality: Quality

        public enum Gender: String, Codable, Sendable {
            case female = "Female"
            case male = "Male"
        }

        public enum Quality: String, Codable, Sendable {
            case a = "A"  // Higher quality
            case b = "B"  // Standard quality
        }
    }

    /// All available Kokoro voices (36 total: 28 English + 8 Romance)
    public static let availableVoices: [VoiceDefinition] = [
        // === American English - Female (11 voices) ===
        VoiceDefinition(id: "af_alloy", name: "Alloy", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_aoede", name: "Aoede", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_bella", name: "Bella", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_heart", name: "Heart", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_jessica", name: "Jessica", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_kore", name: "Kore", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_nicole", name: "Nicole", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_nova", name: "Nova", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_river", name: "River", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_sarah", name: "Sarah", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_sky", name: "Sky", language: "en-US", gender: .female, quality: .a),

        // === American English - Male (9 voices) ===
        VoiceDefinition(id: "am_adam", name: "Adam", language: "en-US", gender: .male, quality: .a),
        VoiceDefinition(id: "am_echo", name: "Echo", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_eric", name: "Eric", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_fenrir", name: "Fenrir", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_liam", name: "Liam", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_michael", name: "Michael", language: "en-US", gender: .male, quality: .a),
        VoiceDefinition(id: "am_onyx", name: "Onyx", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_puck", name: "Puck", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_santa", name: "Santa", language: "en-US", gender: .male, quality: .b),

        // === British English - Female (4 voices) ===
        VoiceDefinition(id: "bf_alice", name: "Alice", language: "en-GB", gender: .female, quality: .a),
        VoiceDefinition(id: "bf_emma", name: "Emma", language: "en-GB", gender: .female, quality: .b),
        VoiceDefinition(id: "bf_isabella", name: "Isabella", language: "en-GB", gender: .female, quality: .b),
        VoiceDefinition(id: "bf_lily", name: "Lily", language: "en-GB", gender: .female, quality: .b),

        // === British English - Male (4 voices) ===
        VoiceDefinition(id: "bm_daniel", name: "Daniel", language: "en-GB", gender: .male, quality: .a),
        VoiceDefinition(id: "bm_fable", name: "Fable", language: "en-GB", gender: .male, quality: .b),
        VoiceDefinition(id: "bm_george", name: "George", language: "en-GB", gender: .male, quality: .b),
        VoiceDefinition(id: "bm_lewis", name: "Lewis", language: "en-GB", gender: .male, quality: .b),

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

    /// Get voice definition by ID
    public static func voiceDefinition(forId id: String) -> VoiceDefinition? {
        return availableVoices.first { $0.id == id }
    }

    /// Get default voice definitions (one per language enabled by default)
    public static var defaultEnabledVoiceIds: [String] {
        return SupportedLanguage.allCases.map { $0.defaultVoiceId }
        // ["af_heart", "bf_emma", "ef_dora", "if_sara", "pf_dora"]
    }
}
