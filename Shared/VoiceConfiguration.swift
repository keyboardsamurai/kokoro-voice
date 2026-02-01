// Shared/VoiceConfiguration.swift
// KokoroVoice
//
// Voice configuration model and persistence manager.
// Shared between host app and extension via App Groups.

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Voice Configuration Model

/// Represents a single voice configuration with its settings
public struct VoiceConfiguration: Codable, Identifiable, Equatable, Hashable {

    // MARK: - Nested Types

    public enum Gender: String, Codable, CaseIterable {
        case female = "Female"
        case male = "Male"
    }

    public enum Quality: String, Codable, CaseIterable {
        case a = "A"  // Higher quality
        case b = "B"  // Standard quality
    }

    // MARK: - Properties

    /// Unique voice identifier (e.g., "af_heart")
    public let id: String

    /// Voice display name (e.g., "Kokoro Heart")
    public let name: String

    /// Language/locale code (e.g., "en-US", "en-GB")
    public let language: String

    /// Voice gender
    public let gender: Gender

    /// Voice quality tier
    public let quality: Quality

    /// Whether this voice is enabled for system use
    public var isEnabled: Bool

    // MARK: - Computed Properties

    /// Full system voice identifier
    public var identifier: String {
        Constants.voiceIdentifierPrefix + id
    }

    /// Display name with gender suffix
    public var displayName: String {
        "\(name) (\(gender.rawValue))"
    }

    /// BCP-47 language tag
    public var languageTag: Locale.LanguageCode {
        Locale.LanguageCode(id.prefix(2) == "bf" || id.prefix(2) == "bm" ? "en" : "en")
    }

    /// Voice file name (without extension)
    public var voiceFileName: String {
        id
    }

    // MARK: - Initialization

    public init(
        id: String,
        name: String,
        language: String,
        gender: Gender,
        quality: Quality,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.gender = gender
        self.quality = quality
        self.isEnabled = isEnabled
    }

    /// Initialize from a voice definition
    public init(from definition: Constants.VoiceDefinition, isEnabled: Bool) {
        self.id = definition.id
        self.name = definition.name
        self.language = definition.language
        self.gender = definition.gender == .female ? .female : .male
        self.quality = definition.quality == .a ? .a : .b
        self.isEnabled = isEnabled
    }
}

// MARK: - Voice Configuration Manager

/// Manages voice configurations persistence via App Groups (when available) or standard UserDefaults
public final class VoiceConfigurationManager: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance using the app group identifier with fallback to standard UserDefaults
    public static let shared = VoiceConfigurationManager(suiteName: Constants.appGroupIdentifier)

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let suiteName: String
    private let isUsingAppGroup: Bool

    // MARK: - Initialization

    /// Initialize with a specific UserDefaults suite name
    /// Falls back to standard UserDefaults if App Group is unavailable (unsigned builds)
    /// - Parameter suiteName: The UserDefaults suite name (usually app group identifier)
    public init(suiteName: String?) {
        self.suiteName = suiteName ?? "standard"

        // Try App Group first, fall back to standard UserDefaults for unsigned builds
        if let suiteName = suiteName,
           let groupDefaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = groupDefaults
            self.isUsingAppGroup = true
        } else {
            self.userDefaults = UserDefaults.standard
            self.isUsingAppGroup = false
            print("VoiceConfigurationManager: App Group unavailable, using standard UserDefaults (all voices enabled)")
        }
    }

    // MARK: - Public Methods

    /// Whether App Group storage is available (signed builds only)
    public var hasAppGroupAccess: Bool {
        isUsingAppGroup
    }

    /// Get all voice configurations
    /// - Returns: Array of all voice configurations, or default configurations if none saved
    ///           For unsigned builds (no App Group), all voices are always enabled
    public func getAllVoices() -> [VoiceConfiguration] {
        // For unsigned builds without App Group, always return all voices enabled
        if !isUsingAppGroup {
            return createAllVoicesEnabledConfiguration()
        }

        if let data = userDefaults.data(forKey: Constants.voicesKey),
           let voices = try? JSONDecoder().decode([VoiceConfiguration].self, from: data) {
            return voices
        }

        // No saved configuration - create defaults with selected voices enabled
        let defaults = createDefaultVoiceConfigurations()

        // Save defaults for next time to ensure persistence
        if let data = try? JSONEncoder().encode(defaults) {
            userDefaults.set(data, forKey: Constants.voicesKey)
            userDefaults.synchronize()
        }

        return defaults
    }

    /// Get only enabled voice configurations
    /// - Returns: Array of enabled voice configurations
    public func getEnabledVoices() -> [VoiceConfiguration] {
        return getAllVoices().filter { $0.isEnabled }
    }

    /// Get a specific voice by ID
    /// - Parameter id: The voice ID to search for
    /// - Returns: The voice configuration if found, nil otherwise
    public func getVoice(byId id: String) -> VoiceConfiguration? {
        return getAllVoices().first { $0.id == id }
    }

    /// Save voice configurations
    /// - Parameter voices: Array of voice configurations to save
    public func saveVoiceConfigurations(_ voices: [VoiceConfiguration]) {
        // Skip saving for unsigned builds - all voices are always enabled
        guard isUsingAppGroup else { return }

        guard let data = try? JSONEncoder().encode(voices) else {
            print("VoiceConfigurationManager: Failed to encode voice configurations")
            return
        }
        userDefaults.set(data, forKey: Constants.voicesKey)
        userDefaults.synchronize()

        // Notify system of voice changes
        notifySystemOfVoiceChanges()
    }

    /// Toggle a voice's enabled state
    /// - Parameter id: The voice ID to toggle
    public func toggleVoice(withId id: String) {
        var voices = getAllVoices()
        guard let index = voices.firstIndex(where: { $0.id == id }) else {
            print("VoiceConfigurationManager: Voice not found: \(id)")
            return
        }
        voices[index].isEnabled.toggle()
        saveVoiceConfigurations(voices)
    }

    /// Set a voice's enabled state
    /// - Parameters:
    ///   - id: The voice ID to modify
    ///   - enabled: Whether the voice should be enabled
    public func setVoiceEnabled(withId id: String, enabled: Bool) {
        var voices = getAllVoices()
        guard let index = voices.firstIndex(where: { $0.id == id }) else {
            print("VoiceConfigurationManager: Voice not found: \(id)")
            return
        }
        voices[index].isEnabled = enabled
        saveVoiceConfigurations(voices)
    }

    /// Clear all saved voice configurations
    public func clearAll() {
        guard isUsingAppGroup else { return }
        userDefaults.removeObject(forKey: Constants.voicesKey)
        userDefaults.synchronize()
    }

    // MARK: - Private Methods

    /// Create voice configurations with all voices enabled (for unsigned builds)
    private func createAllVoicesEnabledConfiguration() -> [VoiceConfiguration] {
        return Constants.availableVoices.map { definition in
            VoiceConfiguration(from: definition, isEnabled: true)
        }
    }

    /// Create default voice configurations from available voices
    private func createDefaultVoiceConfigurations() -> [VoiceConfiguration] {
        let defaultEnabled = Set(Constants.defaultEnabledVoiceIds)

        return Constants.availableVoices.map { definition in
            VoiceConfiguration(
                from: definition,
                isEnabled: defaultEnabled.contains(definition.id)
            )
        }
    }

    /// Notify the system that available voices have changed
    private func notifySystemOfVoiceChanges() {
        #if canImport(AVFoundation)
        // Only available on macOS 13+ / iOS 16+
        if #available(macOS 13.0, iOS 16.0, *) {
            AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        }
        #endif
    }
}

// MARK: - Extension for Compatibility

extension VoiceConfiguration {

    /// Check if voice is for British English
    public var isBritishEnglish: Bool {
        language == "en-GB" || id.hasPrefix("b")
    }

    /// Check if voice is for American English
    public var isAmericanEnglish: Bool {
        language == "en-US" || id.hasPrefix("a")
    }

    /// Check if voice is for Spanish
    public var isSpanish: Bool {
        language == "es-ES" || id.hasPrefix("e")
    }

    /// Check if voice is for Italian
    public var isItalian: Bool {
        language == "it-IT" || id.hasPrefix("i")
    }

    /// Check if voice is for Brazilian Portuguese
    public var isBrazilianPortuguese: Bool {
        language == "pt-BR" || id.hasPrefix("p")
    }

    /// Check if voice is for a Romance language (non-English)
    public var isRomanceLanguage: Bool {
        isSpanish || isItalian || isBrazilianPortuguese
    }

    /// Get the Kokoro language enum value (for engine)
    /// Uses the language property with ID-prefix fallback for safety
    public var kokoroLanguageCode: String {
        // Validate the language property against known values
        if let lang = SupportedLanguage(rawValue: language) {
            return lang.rawValue
        }

        // Fallback: infer from voice ID prefix if language is invalid/empty
        let prefix = String(id.prefix(2))
        switch prefix {
        case "af", "am": return "en-US"
        case "bf", "bm": return "en-GB"
        case "ef", "em": return "es-ES"
        case "if", "im": return "it-IT"
        case "pf", "pm": return "pt-BR"
        default:
            // Last resort: return whatever was stored
            return language.isEmpty ? "en-US" : language
        }
    }

    /// Get the supported language enum for this voice
    public var supportedLanguage: SupportedLanguage? {
        SupportedLanguage(rawValue: language)
    }
}
