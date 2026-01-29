// KokoroVoice/VoiceManager.swift
// KokoroVoice
//
// ObservableObject that manages voice state for the host app UI.
// Handles voice enable/disable, testing, and synchronization with system.

import Foundation
import SwiftUI
import AVFoundation
import Combine

// MARK: - Voice Manager

/// Manages voice configurations and provides UI state
@MainActor
public class VoiceManager: ObservableObject {

    // MARK: - Published Properties

    /// All available voice configurations
    @Published public var voices: [VoiceConfiguration] = []

    /// Currently selected voice for testing
    @Published public var selectedVoiceId: String?

    /// Loading state indicator
    @Published public var isLoading = false

    /// Error message if any
    @Published public var errorMessage: String?

    /// Model loading status
    @Published public var modelStatus: ModelStatus = .notLoaded

    // MARK: - Model Status

    public enum ModelStatus {
        case notLoaded
        case loading
        case loaded
        case error(String)

        var description: String {
            switch self {
            case .notLoaded: return "Not loaded"
            case .loading: return "Loading..."
            case .loaded: return "Ready"
            case .error(let message): return "Error: \(message)"
            }
        }

        var isReady: Bool {
            if case .loaded = self { return true }
            return false
        }
    }

    // MARK: - Private Properties

    private let configManager = VoiceConfigurationManager.shared
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        loadVoices()
        setupNotifications()
    }

    // MARK: - Voice Loading

    /// Load voices from configuration manager
    public func loadVoices() {
        isLoading = true

        // Load all configurations
        voices = configManager.getAllVoices()

        // Check system available voices
        checkSystemVoices()

        isLoading = false
    }

    /// Refresh voice list
    public func refreshVoices() {
        loadVoices()
    }

    // MARK: - Voice Management

    /// Toggle a voice's enabled state
    public func toggleVoice(_ voice: VoiceConfiguration) {
        configManager.toggleVoice(withId: voice.id)
        loadVoices()
    }

    /// Set a voice's enabled state
    public func setVoiceEnabled(_ voice: VoiceConfiguration, enabled: Bool) {
        configManager.setVoiceEnabled(withId: voice.id, enabled: enabled)
        loadVoices()
    }

    /// Enable all voices
    public func enableAllVoices() {
        var updated = voices
        for index in updated.indices {
            updated[index].isEnabled = true
        }
        configManager.saveVoiceConfigurations(updated)
        loadVoices()
    }

    /// Disable all voices
    public func disableAllVoices() {
        var updated = voices
        for index in updated.indices {
            updated[index].isEnabled = false
        }
        configManager.saveVoiceConfigurations(updated)
        loadVoices()
    }

    // MARK: - Voice Testing

    /// Test a voice by speaking sample text
    public func testVoice(_ voice: VoiceConfiguration, text: String? = nil) {
        // Cancel any ongoing speech
        stopSpeaking()

        // Create synthesizer if needed
        if speechSynthesizer == nil {
            speechSynthesizer = AVSpeechSynthesizer()
        }

        let sampleText = text ?? "Hello! This is the \(voice.name) voice from Kokoro."
        let utterance = AVSpeechUtterance(string: sampleText)

        // Try to use the Kokoro voice if available
        if let systemVoice = AVSpeechSynthesisVoice(identifier: voice.identifier) {
            utterance.voice = systemVoice
        } else {
            // Fall back to a system voice for the same language
            utterance.voice = AVSpeechSynthesisVoice(language: voice.language)
            print("VoiceManager: Kokoro voice not available, using system fallback")
        }

        // Speak
        speechSynthesizer?.speak(utterance)
        selectedVoiceId = voice.id
    }

    /// Stop any ongoing speech
    public func stopSpeaking() {
        speechSynthesizer?.stopSpeaking(at: .immediate)
        selectedVoiceId = nil
    }

    /// Check if a voice is currently speaking
    public var isSpeaking: Bool {
        return speechSynthesizer?.isSpeaking ?? false
    }

    // MARK: - System Voice Check

    /// Check which Kokoro voices are registered with the system
    private func checkSystemVoices() {
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let kokoroIdentifiers = Set(systemVoices.filter {
            $0.identifier.hasPrefix(Constants.voiceIdentifierPrefix)
        }.map { $0.identifier })

        // Log registered voices
        if kokoroIdentifiers.isEmpty {
            print("VoiceManager: No Kokoro voices registered with system")
        } else {
            print("VoiceManager: Found \(kokoroIdentifiers.count) Kokoro voices registered")
            for id in kokoroIdentifiers {
                print("  - \(id)")
            }
        }
    }

    /// Check if a specific voice is registered with the system
    public func isVoiceRegisteredWithSystem(_ voice: VoiceConfiguration) -> Bool {
        return AVSpeechSynthesisVoice(identifier: voice.identifier) != nil
    }

    // MARK: - Notifications

    private func setupNotifications() {
        // Listen for system voice changes
        NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadVoices()
            }
            .store(in: &cancellables)
    }

    // MARK: - Model Status

    /// Update model loading status
    public func updateModelStatus() async {
        modelStatus = .loading

        // Check if model is available
        let isLoaded = await KokoroEngine.shared.isModelLoaded

        await MainActor.run {
            modelStatus = isLoaded ? .loaded : .notLoaded
        }
    }
}

// MARK: - Voice Filtering

extension VoiceManager {

    /// Get voices filtered by language
    public func voices(forLanguage language: String) -> [VoiceConfiguration] {
        return voices.filter { $0.language == language }
    }

    /// Get voices filtered by gender
    public func voices(forGender gender: VoiceConfiguration.Gender) -> [VoiceConfiguration] {
        return voices.filter { $0.gender == gender }
    }

    /// Get enabled voices only
    public var enabledVoices: [VoiceConfiguration] {
        return voices.filter { $0.isEnabled }
    }

    /// Get disabled voices only
    public var disabledVoices: [VoiceConfiguration] {
        return voices.filter { !$0.isEnabled }
    }

    /// Group voices by language
    public var voicesByLanguage: [String: [VoiceConfiguration]] {
        Dictionary(grouping: voices) { $0.language }
    }

    /// Group voices by gender
    public var voicesByGender: [VoiceConfiguration.Gender: [VoiceConfiguration]] {
        Dictionary(grouping: voices) { $0.gender }
    }
}
