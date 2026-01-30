// KokoroVoice/VoiceManager.swift
// KokoroVoice
//
// ObservableObject that manages voice state for the host app UI.
// Handles voice enable/disable, testing, and synchronization with system.
//
// Dependencies:
// - VoiceConfiguration.swift (defines VoiceConfiguration and VoiceConfigurationManager)
// - Constants.swift (defines shared constants)
// - KokoroEngine.swift (defines Kokoro TTS engine)

import Foundation
import SwiftUI
import AVFoundation
import Combine
import KokoroVoiceShared

// MARK: - Voice Manager

/// Manages voice configurations and provides UI state
@MainActor
public class VoiceManager: NSObject, ObservableObject {

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

    /// Whether a voice is currently being tested
    @Published public var isSpeaking = false

    // MARK: - Private Properties

    private let configManager = VoiceConfigurationManager.shared
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var audioPlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public override init() {
        super.init()
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

    /// Test a voice by speaking sample text using KokoroEngine directly
    public func testVoice(_ voice: VoiceConfiguration, text: String? = nil) {
        stopSpeaking()
        selectedVoiceId = voice.id
        isSpeaking = true

        let sampleText = text ?? "Hello! This is the \(voice.name) voice from Kokoro."

        Task {
            do {
                // Ensure model is loaded
                let modelLoaded = await KokoroEngine.shared.isModelLoaded
                if !modelLoaded {
                    let modelPath = Bundle.main.resourceURL ?? Bundle.main.bundleURL
                    try await KokoroEngine.shared.loadModel(from: modelPath)
                }

                // Generate audio using Kokoro TTS directly
                let samples = try await KokoroEngine.shared.generateAudio(
                    text: sampleText,
                    voiceId: voice.id,
                    speed: 1.0
                )

                guard !samples.isEmpty else {
                    print("VoiceManager: No audio generated")
                    await MainActor.run {
                        isSpeaking = false
                        selectedVoiceId = nil
                    }
                    return
                }

                // Convert Float array to audio data and play
                await playAudioSamples(samples)
            } catch {
                print("VoiceManager: TTS error: \(error)")
                await MainActor.run {
                    isSpeaking = false
                    selectedVoiceId = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Play audio samples through AVAudioPlayer
    private func playAudioSamples(_ samples: [Float]) async {
        let audioData = createWAVData(from: samples, sampleRate: Constants.sampleRate)

        await MainActor.run {
            do {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.delegate = self
                audioPlayer?.play()
            } catch {
                print("VoiceManager: Playback error: \(error)")
                isSpeaking = false
                selectedVoiceId = nil
            }
        }
    }

    /// Create WAV data from Float32 samples
    private func createWAVData(from samples: [Float], sampleRate: Double) -> Data {
        var data = Data()

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2) // 16-bit = 2 bytes per sample
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert Float32 samples to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Value.littleEndian) { Array($0) })
        }

        return data
    }

    /// Stop any ongoing speech
    public func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        speechSynthesizer?.stopSpeaking(at: .immediate)
        isSpeaking = false
        selectedVoiceId = nil
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

// MARK: - AVAudioPlayerDelegate

extension VoiceManager: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isSpeaking = false
            selectedVoiceId = nil
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            isSpeaking = false
            selectedVoiceId = nil
            if let error = error {
                print("VoiceManager: Audio decode error: \(error)")
            }
        }
    }
}
