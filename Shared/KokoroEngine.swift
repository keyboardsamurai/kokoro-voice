// Shared/KokoroEngine.swift
// KokoroVoice
//
// Wrapper around KokoroTTS that handles model loading and audio generation.
// This provides a clean interface for the Speech Synthesis Provider extension.

import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(KokoroSwift)
import KokoroSwift
#endif

#if canImport(MLX)
import MLX
#endif

#if canImport(MLXUtilsLibrary)
import MLXUtilsLibrary
#endif

// MARK: - Kokoro Engine Errors

/// Errors that can occur during Kokoro TTS operations
public enum KokoroEngineError: Error, LocalizedError {
    case modelNotLoaded
    case voiceNotFound(String)
    case synthesisError(String)
    case modelLoadError(String)
    case voiceEmbeddingLoadError(String)
    case invalidAudioFormat

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Kokoro TTS model is not loaded"
        case .voiceNotFound(let voiceId):
            return "Voice not found: \(voiceId)"
        case .synthesisError(let message):
            return "Synthesis error: \(message)"
        case .modelLoadError(let message):
            return "Failed to load model: \(message)"
        case .voiceEmbeddingLoadError(let message):
            return "Failed to load voice embedding: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
}

// MARK: - Kokoro Language

/// Supported languages for Kokoro TTS
public enum KokoroLanguage: String, CaseIterable {
    case enUS = "en-US"
    case enGB = "en-GB"
    case spanish = "es-ES"
    case italian = "it-IT"
    case brazilianPortuguese = "pt-BR"

    /// Get the language from a voice ID based on prefix
    /// Voice ID prefixes:
    /// - a: American English (af_, am_)
    /// - b: British English (bf_, bm_)
    /// - e: Spanish (ef_, em_)
    /// - i: Italian (if_, im_)
    /// - p: Portuguese (pf_, pm_)
    public static func from(voiceId: String) -> KokoroLanguage {
        guard voiceId.count >= 2 else { return .enUS }
        let prefix = String(voiceId.prefix(1))

        switch prefix {
        case "b": return .enGB
        case "e": return .spanish
        case "i": return .italian
        case "p": return .brazilianPortuguese
        default: return .enUS  // 'a' and unknown default to en-US
        }
    }

    /// Get the language from a language string
    public static func from(languageString: String) -> KokoroLanguage? {
        return SupportedLanguage(rawValue: languageString).flatMap { supported in
            KokoroLanguage(rawValue: supported.rawValue)
        }
    }

    #if canImport(KokoroSwift)
    /// Convert to KokoroSwift Language enum
    var kokoroLanguage: Language {
        switch self {
        case .enUS:
            return .enUS
        case .enGB:
            return .enGB
        case .spanish:
            return .spanish
        case .italian:
            return .italian
        case .brazilianPortuguese:
            return .brazilianPortuguese
        }
    }
    #endif
}

// MARK: - Kokoro Engine

/// Main engine wrapper for Kokoro TTS
/// Thread-safe singleton that manages model loading and audio synthesis
public actor KokoroEngine {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = KokoroEngine()

    // MARK: - Properties

    #if canImport(KokoroSwift)
    private var tts: KokoroTTS?
    #endif

    private var isLoaded = false
    private var isLoading = false
    private var modelPath: URL?

    // Voice embeddings cache - MLXArray embeddings keyed by voice ID
    #if canImport(MLX)
    private var voiceEmbeddings: [String: MLXArray] = [:]
    #else
    private var voiceEmbeddings: [String: Any] = [:]
    #endif

    // MARK: - Initialization

    private init() {}

    // MARK: - Model Loading

    /// Check if the model is loaded
    public var isModelLoaded: Bool {
        return isLoaded
    }

    /// Load the Kokoro model and voice embeddings
    /// - Parameter modelPath: Path to the directory containing model files
    /// - Throws: KokoroEngineError if loading fails
    public func loadModel(from modelPath: URL) async throws {
        // Prevent concurrent loading
        guard !isLoading else { return }
        guard !isLoaded else { return }

        isLoading = true
        defer { isLoading = false }

        self.modelPath = modelPath

        #if canImport(KokoroSwift)
        do {
            // Initialize the TTS engine with the model file and composite G2P processor
            // Composite G2P routes English to Misaki, Romance languages to rule-based G2P
            let modelFile = modelPath.appendingPathComponent("kokoro-v1_0.safetensors")
            tts = try KokoroTTS(modelPath: modelFile, g2p: .composite)

            // Preload voice embeddings from voices.npz archive
            try await loadVoiceEmbeddings(from: modelPath)

            isLoaded = true
            print("KokoroEngine: Model loaded successfully from \(modelPath.path)")
        } catch {
            throw KokoroEngineError.modelLoadError(error.localizedDescription)
        }
        #else
        // Stub for platforms without KokoroSwift
        print("KokoroEngine: KokoroSwift not available, using stub implementation")
        isLoaded = true
        #endif
    }

    /// Load voice embeddings from safetensors files, voices.npz archive, or individual .npy files
    /// Supports multiple formats in order of preference:
    /// 1. Individual .safetensors files in voices/ directory (mlx-community format)
    /// 2. voices.npz archive (Kokoro format)
    /// 3. Individual .npy files in voices/ directory (fallback)
    private func loadVoiceEmbeddings(from modelPath: URL) async throws {
        let fileManager = FileManager.default
        let voicesPath = modelPath.appendingPathComponent("voices")

        #if canImport(MLX)
        // Try loading from voices/*.safetensors first (mlx-community format)
        if fileManager.fileExists(atPath: voicesPath.path) {
            do {
                let voiceFiles = try fileManager.contentsOfDirectory(at: voicesPath, includingPropertiesForKeys: nil)
                let safetensorsFiles = voiceFiles.filter { $0.pathExtension == "safetensors" }

                if !safetensorsFiles.isEmpty {
                    for voiceFile in safetensorsFiles {
                        do {
                            // loadArrays returns [String: MLXArray] for the tensors in the file
                            let tensors = try loadArrays(url: voiceFile)

                            // Voice safetensors typically contain one tensor, take the first one
                            if let embedding = tensors.values.first {
                                let voiceId = voiceFile.deletingPathExtension().lastPathComponent
                                voiceEmbeddings[voiceId] = embedding
                                print("KokoroEngine: Loaded voice embedding for \(voiceId) from safetensors")
                            }
                        } catch {
                            print("KokoroEngine: Failed to load \(voiceFile.lastPathComponent): \(error)")
                        }
                    }

                    if !voiceEmbeddings.isEmpty {
                        print("KokoroEngine: Loaded \(voiceEmbeddings.count) voice embeddings from safetensors files")
                        return
                    }
                }
            } catch {
                print("KokoroEngine: Error scanning voices directory: \(error)")
            }
        }
        #endif

        #if canImport(MLX)
        // Try loading from voices.npz archive (Kokoro format)
        let voicesNpzPath = modelPath.appendingPathComponent("voices.npz")
        if fileManager.fileExists(atPath: voicesNpzPath.path) {
            if let allVoices = NpyzReader.read(fileFromPath: voicesNpzPath) {
                for (key, embedding) in allVoices {
                    // Keys may be like "af_heart.npy" or just "af_heart"
                    let voiceId = key.hasSuffix(".npy")
                        ? String(key.dropLast(4))  // Remove .npy extension
                        : key
                    voiceEmbeddings[voiceId] = embedding
                    print("KokoroEngine: Loaded voice embedding for \(voiceId) from npz")
                }
                print("KokoroEngine: Loaded \(voiceEmbeddings.count) voice embeddings from voices.npz")
                return
            }
        }

        // Fallback: Try loading individual .npy files from voices directory
        if fileManager.fileExists(atPath: voicesPath.path) {
            do {
                let voiceFiles = try fileManager.contentsOfDirectory(at: voicesPath, includingPropertiesForKeys: nil)
                let npyFiles = voiceFiles.filter { $0.pathExtension == "npy" }

                for voiceFile in npyFiles {
                    if let embedding = NpyzReader.read(fileFromPath: voiceFile)?["npy"] {
                        let voiceId = voiceFile.deletingPathExtension().lastPathComponent
                        voiceEmbeddings[voiceId] = embedding
                        print("KokoroEngine: Loaded voice embedding for \(voiceId) from npy")
                    }
                }
                print("KokoroEngine: Loaded \(voiceEmbeddings.count) voice embeddings from individual npy files")
            } catch {
                print("KokoroEngine: Error loading voice embeddings: \(error)")
            }
        }
        #else
        // Without MLXUtilsLibrary/MLX, mark expected voices as available for testing
        for voice in Constants.availableVoices {
            voiceEmbeddings[voice.id] = true as Any
        }
        print("KokoroEngine: MLX/MLXUtilsLibrary not available, using stub voice embeddings")
        #endif
    }

    // MARK: - Audio Generation

    /// Generate audio from text using the specified voice
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voiceId: Voice identifier (e.g., "af_heart")
    ///   - speed: Speech speed multiplier (1.0 = normal)
    /// - Returns: Audio samples as Float32 array at 24kHz sample rate
    /// - Throws: KokoroEngineError if synthesis fails
    public func generateAudio(text: String, voiceId: String, speed: Float = 1.0) async throws -> [Float] {
        guard isLoaded else {
            throw KokoroEngineError.modelNotLoaded
        }

        // Handle empty text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        #if canImport(KokoroSwift) && canImport(MLX)
        guard let tts = tts else {
            throw KokoroEngineError.modelNotLoaded
        }

        // Get voice embedding, fall back to default if not found
        let effectiveVoiceId = voiceEmbeddings[voiceId] != nil ? voiceId : Constants.defaultVoice

        guard let voiceEmbedding = voiceEmbeddings[effectiveVoiceId] else {
            throw KokoroEngineError.voiceNotFound(voiceId)
        }

        // Determine language from voice ID
        let language = KokoroLanguage.from(voiceId: effectiveVoiceId)

        do {
            // Generate audio using KokoroTTS with MLXArray voice embedding
            // API: generateAudio(voice: MLXArray, language: Language, text: String, speed: Float) -> (AudioBuffer, timestamps)
            let (audioBuffer, _) = try tts.generateAudio(
                voice: voiceEmbedding,
                language: language.kokoroLanguage,
                text: text,
                speed: speed
            )
            return audioBuffer
        } catch {
            throw KokoroEngineError.synthesisError(error.localizedDescription)
        }
        #else
        // Stub implementation for testing - generate silence with approximate duration
        let estimatedDuration = Double(text.count) * 0.06 / Double(speed)  // ~60ms per character
        return generateSilence(duration: estimatedDuration)
        #endif
    }

    /// Generate silence of the specified duration
    /// - Parameter duration: Duration in seconds
    /// - Returns: Array of silent audio samples
    public func generateSilence(duration: Double) -> [Float] {
        let sampleCount = Int(duration * Constants.sampleRate)
        return [Float](repeating: 0.0, count: max(0, sampleCount))
    }

    // MARK: - Voice Information

    /// Get list of available voice IDs
    public func availableVoiceIds() -> [String] {
        return Array(voiceEmbeddings.keys)
    }

    /// Check if a specific voice is available
    public func isVoiceAvailable(_ voiceId: String) -> Bool {
        return voiceEmbeddings[voiceId] != nil
    }

    // MARK: - Cleanup

    /// Unload the model and free resources
    public func unloadModel() {
        #if canImport(KokoroSwift)
        tts = nil
        #endif
        voiceEmbeddings.removeAll()
        isLoaded = false
        print("KokoroEngine: Model unloaded")
    }
}

// MARK: - Audio Buffer Utilities

/// Utility functions for audio buffer manipulation
public enum AudioBufferUtils {

    /// Create an audio buffer from Float32 samples
    /// - Parameters:
    ///   - samples: Array of Float32 audio samples
    ///   - sampleRate: Sample rate (default: 24000)
    /// - Returns: AVAudioPCMBuffer if available, nil otherwise
    #if canImport(AVFoundation)
    public static func createPCMBuffer(from samples: [Float], sampleRate: Double = Constants.sampleRate) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(Constants.channelCount),
            interleaved: false
        ) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }

        return buffer
    }
    #endif

    /// Normalize audio samples to prevent clipping
    /// - Parameter samples: Audio samples to normalize
    /// - Returns: Normalized samples with peak at 0.95
    public static func normalize(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let maxAbs = samples.map { abs($0) }.max() ?? 1.0
        guard maxAbs > 0 else { return samples }

        let scale = 0.95 / maxAbs
        return samples.map { $0 * scale }
    }

    /// Apply a simple fade in/out to audio samples
    /// - Parameters:
    ///   - samples: Audio samples
    ///   - fadeInSamples: Number of samples for fade in
    ///   - fadeOutSamples: Number of samples for fade out
    /// - Returns: Samples with fades applied
    public static func applyFades(to samples: [Float], fadeInSamples: Int = 100, fadeOutSamples: Int = 100) -> [Float] {
        guard samples.count > fadeInSamples + fadeOutSamples else { return samples }

        var result = samples

        // Fade in
        for i in 0..<fadeInSamples {
            let factor = Float(i) / Float(fadeInSamples)
            result[i] *= factor
        }

        // Fade out
        let fadeOutStart = samples.count - fadeOutSamples
        for i in 0..<fadeOutSamples {
            let factor = Float(fadeOutSamples - i) / Float(fadeOutSamples)
            result[fadeOutStart + i] *= factor
        }

        return result
    }
}
