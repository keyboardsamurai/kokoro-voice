// Shared/Constants.swift
// KokoroVoice
//
// Shared constants used by both the host app and the extension.

import Foundation

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

    /// All available Kokoro voices
    public static let availableVoices: [VoiceDefinition] = [
        // American English - Female
        VoiceDefinition(id: "af_alloy", name: "Kokoro Alloy", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_aoede", name: "Kokoro Aoede", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_bella", name: "Kokoro Bella", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_heart", name: "Kokoro Heart", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_jessica", name: "Kokoro Jessica", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_kore", name: "Kokoro Kore", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_nicole", name: "Kokoro Nicole", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_nova", name: "Kokoro Nova", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_river", name: "Kokoro River", language: "en-US", gender: .female, quality: .b),
        VoiceDefinition(id: "af_sarah", name: "Kokoro Sarah", language: "en-US", gender: .female, quality: .a),
        VoiceDefinition(id: "af_sky", name: "Kokoro Sky", language: "en-US", gender: .female, quality: .a),

        // American English - Male
        VoiceDefinition(id: "am_adam", name: "Kokoro Adam", language: "en-US", gender: .male, quality: .a),
        VoiceDefinition(id: "am_echo", name: "Kokoro Echo", language: "en-US", gender: .male, quality: .b),
        VoiceDefinition(id: "am_michael", name: "Kokoro Michael", language: "en-US", gender: .male, quality: .a),

        // British English - Female
        VoiceDefinition(id: "bf_alice", name: "Kokoro Alice", language: "en-GB", gender: .female, quality: .a),
        VoiceDefinition(id: "bf_emma", name: "Kokoro Emma", language: "en-GB", gender: .female, quality: .b),

        // British English - Male
        VoiceDefinition(id: "bm_daniel", name: "Kokoro Daniel", language: "en-GB", gender: .male, quality: .a),
        VoiceDefinition(id: "bm_george", name: "Kokoro George", language: "en-GB", gender: .male, quality: .b),
    ]

    /// Get voice definition by ID
    public static func voiceDefinition(forId id: String) -> VoiceDefinition? {
        return availableVoices.first { $0.id == id }
    }

    /// Get default voice definitions (first 3 voices enabled by default)
    public static var defaultEnabledVoiceIds: [String] {
        return ["af_heart", "am_adam", "bf_alice"]
    }
}
