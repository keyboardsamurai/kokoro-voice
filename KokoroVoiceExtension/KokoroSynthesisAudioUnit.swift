// KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift
// KokoroVoice
//
// Main Audio Unit class implementing AVSpeechSynthesisProviderAudioUnit
// for the Kokoro TTS Speech Synthesis Provider.

import Foundation
import AVFoundation
import AudioToolbox
import KokoroVoiceShared

#if os(macOS)
import AppKit
import CoreAudioKit
#endif

// MARK: - Kokoro Synthesis Audio Unit

/// Main Audio Unit for Kokoro Speech Synthesis Provider
/// This class bridges the system's speech synthesis requests to the Kokoro TTS engine.
@available(macOS 13.0, iOS 16.0, *)
public final class KokoroSynthesisAudioUnit: AVSpeechSynthesisProviderAudioUnit, @unchecked Sendable {

    // MARK: - Properties

    /// Reference to voice configuration manager
    private let configManager = VoiceConfigurationManager.shared

    /// Output busses array for audio routing
    private var _outputBusses: AUAudioUnitBusArray!

    /// Current audio buffer containing synthesized speech
    private var currentBuffer: AVAudioPCMBuffer?

    /// Current position in the audio buffer (in frames)
    private var framePosition: AVAudioFramePosition = 0

    /// Current speech request being processed
    private var currentRequest: AVSpeechSynthesisProviderRequest?

    /// Serial queue for synthesis operations
    private let synthesisQueue = DispatchQueue(
        label: "com.kokorovoice.synthesis",
        qos: .userInteractive
    )

    /// Flag indicating if the model is loaded and ready
    private var isModelReady = false

    /// Lock for thread-safe buffer access
    private let bufferLock = NSLock()

    /// Pending requests queue (for when model isn't ready)
    private var pendingRequests: [AVSpeechSynthesisProviderRequest] = []

    /// Flag indicating synthesis completed with empty result
    private var synthesisCompletedEmpty = false

    // MARK: - Initialization

    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        // Set up output bus with correct audio format
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.sampleRate,
            channels: AVAudioChannelCount(Constants.channelCount),
            interleaved: false
        ) else {
            throw NSError(domain: "KokoroSynthesisAudioUnit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output audio format"])
        }

        do {
            let outputBus = try AUAudioUnitBus(format: outputFormat)
            _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        } catch {
            throw NSError(domain: "KokoroSynthesisAudioUnit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output bus: \(error)"])
        }

        // Load model asynchronously
        Task {
            await self.loadModel()
        }

        print("KokoroSynthesisAudioUnit: Initialized with format \(outputFormat)")
    }

    // MARK: - Audio Unit Configuration

    /// Override outputBusses to provide our configured output
    public override var outputBusses: AUAudioUnitBusArray {
        return _outputBusses
    }

    // MARK: - Model Loading

    /// Load the Kokoro TTS model
    private func loadModel() async {
        // Find model resources
        guard let resourceURL = findModelResourceURL() else {
            print("KokoroSynthesisAudioUnit: Could not find model resources")
            return
        }

        do {
            try await KokoroEngine.shared.loadModel(from: resourceURL)
            isModelReady = true
            print("KokoroSynthesisAudioUnit: Model loaded successfully")

            // Process any pending requests
            await processPendingRequests()
        } catch {
            print("KokoroSynthesisAudioUnit: Failed to load model: \(error)")
        }
    }

    /// Find the URL for model resources
    private func findModelResourceURL() -> URL? {
        let fileManager = FileManager.default

        // For extensions embedded in app: navigate from extension bundle to containing app's resources
        // Extension is at: KokoroVoice.app/Contents/PlugIns/KokoroVoiceExtension.appex
        // Resources are at: KokoroVoice.app/Contents/Resources/Resources/
        if let extensionBundle = Bundle(for: type(of: self)).bundleURL as URL? {
            // Go up from .appex to PlugIns, then to Contents, then to Resources
            let appContentsURL = extensionBundle
                .deletingLastPathComponent()  // Remove KokoroVoiceExtension.appex
                .deletingLastPathComponent()  // Remove PlugIns
            let appResourcesURL = appContentsURL.appendingPathComponent("Resources/Resources")

            print("KokoroSynthesisAudioUnit: Checking app resources at \(appResourcesURL.path)")
            if fileManager.fileExists(atPath: appResourcesURL.path) {
                return appResourcesURL
            }

            // Also try without nested Resources folder
            let directResourcesURL = appContentsURL.appendingPathComponent("Resources")
            print("KokoroSynthesisAudioUnit: Checking direct resources at \(directResourcesURL.path)")
            if fileManager.fileExists(atPath: directResourcesURL.appendingPathComponent("kokoro-v1_0.safetensors").path) {
                return directResourcesURL
            }
        }

        // Try extension's own bundle resources
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("Resources") {
            if fileManager.fileExists(atPath: bundleURL.path) {
                return bundleURL
            }
        }

        // Try app group container
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier) {
            let modelsURL = containerURL.appendingPathComponent("Models")
            if fileManager.fileExists(atPath: modelsURL.path) {
                return modelsURL
            }
        }

        // Try main bundle directly
        if let bundleURL = Bundle.main.resourceURL {
            return bundleURL
        }

        return nil
    }

    /// Process any requests that were queued while model was loading
    private func processPendingRequests() async {
        for request in pendingRequests {
            let ssml = request.ssmlRepresentation
            let voiceIdentifier = request.voice.identifier
            await performSynthesis(ssml: ssml, voiceIdentifier: voiceIdentifier)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Voice Registration

    /// Provide available voices to the system
    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            let enabledVoices = configManager.getEnabledVoices()

            // If no voices enabled, fall back to all available voices to prevent crash
            let voicesToReturn = enabledVoices.isEmpty
                ? Constants.availableVoices.map { VoiceConfiguration(from: $0, isEnabled: true) }
                : enabledVoices

            return voicesToReturn.map { config in
                AVSpeechSynthesisProviderVoice(
                    name: config.displayName,
                    identifier: config.identifier,
                    primaryLanguages: [config.language],
                    supportedLanguages: [config.language]
                )
            }
        }
        set {
            // Voice list is managed through VoiceConfigurationManager
        }
    }

    // MARK: - Speech Synthesis

    /// Handle incoming speech synthesis request
    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        print("KokoroSynthesisAudioUnit: Received synthesis request")

        // Store current request
        currentRequest = speechRequest

        // Reset buffer state
        bufferLock.lock()
        currentBuffer = nil
        framePosition = 0
        synthesisCompletedEmpty = false
        bufferLock.unlock()

        // If model isn't ready, queue the request
        guard isModelReady else {
            print("KokoroSynthesisAudioUnit: Model not ready, queueing request")
            pendingRequests.append(speechRequest)
            return
        }

        // Extract data from request synchronously (request may not be Sendable)
        let ssml = speechRequest.ssmlRepresentation
        let voiceIdentifier = speechRequest.voice.identifier

        // Process synthesis using dispatch queue (avoiding Swift 6 sending parameter issues)
        synthesisQueue.async { [self] in
            Task {
                await self.performSynthesis(ssml: ssml, voiceIdentifier: voiceIdentifier)
            }
        }
    }

    /// Perform the actual speech synthesis
    private func performSynthesis(ssml: String, voiceIdentifier: String) async {
        // Parse SSML
        let segments = SSMLParser.parse(ssml)

        // Extract voice ID from identifier
        let voiceId = voiceIdentifier.replacingOccurrences(of: Constants.voiceIdentifierPrefix, with: "")

        print("KokoroSynthesisAudioUnit: Synthesizing for voice: \(voiceId)")
        print("KokoroSynthesisAudioUnit: SSML segments: \(segments.count)")

        var allAudio: [Float] = []

        for segment in segments {
            // Add pause/silence before segment if needed
            if segment.pauseBefore > 0 {
                let silence = await KokoroEngine.shared.generateSilence(duration: segment.pauseBefore)
                allAudio.append(contentsOf: silence)
            }

            // Skip empty text segments
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            // Generate speech audio
            do {
                let audio = try await KokoroEngine.shared.generateAudio(
                    text: text,
                    voiceId: voiceId,
                    speed: segment.rate
                )
                allAudio.append(contentsOf: audio)
            } catch {
                print("KokoroSynthesisAudioUnit: Synthesis error: \(error)")
                // Continue with other segments
            }
        }

        // Handle empty result - signal completion on next render
        guard !allAudio.isEmpty else {
            print("KokoroSynthesisAudioUnit: No audio generated")
            bufferLock.withLock {
                synthesisCompletedEmpty = true
            }
            return
        }

        // Create audio buffer
        let buffer = createAudioBuffer(from: allAudio)

        // Update buffer atomically
        bufferLock.withLock {
            currentBuffer = buffer
            framePosition = 0
        }

        print("KokoroSynthesisAudioUnit: Audio buffer ready, \(allAudio.count) samples")
    }

    /// Cancel the current speech request
    public override func cancelSpeechRequest() {
        print("KokoroSynthesisAudioUnit: Cancelling speech request")

        bufferLock.lock()
        currentRequest = nil
        currentBuffer = nil
        framePosition = 0
        synthesisCompletedEmpty = false
        bufferLock.unlock()

        pendingRequests.removeAll()
    }

    // MARK: - Audio Rendering

    /// Internal render block that provides audio to the system
    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputAudioBufferList, _, _ in
            guard let self = self else {
                return kAudio_ParamError
            }

            self.bufferLock.lock()
            defer { self.bufferLock.unlock() }

            // Get output buffer
            let outputBufferListPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            guard outputBufferListPointer.count > 0 else {
                return kAudio_ParamError
            }

            let outputBuffer = outputBufferListPointer[0]
            guard let outputFrames = outputBuffer.mData?.assumingMemoryBound(to: Float32.self) else {
                return kAudio_ParamError
            }

            // Check if synthesis completed with empty result
            if self.synthesisCompletedEmpty {
                // Output silence and signal completion
                for i in 0..<Int(frameCount) {
                    outputFrames[i] = 0.0
                }
                actionFlags.pointee = .offlineUnitRenderAction_Complete
                self.synthesisCompletedEmpty = false
                print("KokoroSynthesisAudioUnit: Empty synthesis complete")
                return noErr
            }

            // Check if we have audio to output
            guard let buffer = self.currentBuffer,
                  let sourceChannelData = buffer.floatChannelData?[0] else {
                // No audio ready - output silence
                for i in 0..<Int(frameCount) {
                    outputFrames[i] = 0.0
                }
                return noErr
            }

            let bufferLength = AVAudioFramePosition(buffer.frameLength)

            // Copy frames from our buffer to output
            var framesWritten: AVAudioFrameCount = 0

            for frame in 0..<frameCount {
                if self.framePosition < bufferLength {
                    outputFrames[Int(frame)] = sourceChannelData[Int(self.framePosition)]
                    self.framePosition += 1
                    framesWritten += 1
                } else {
                    // Past end of buffer - output silence
                    outputFrames[Int(frame)] = 0.0
                }
            }

            // Check if we've finished playback
            if self.framePosition >= bufferLength {
                // Signal completion
                actionFlags.pointee = .offlineUnitRenderAction_Complete

                // Clean up
                self.currentBuffer = nil
                self.framePosition = 0

                print("KokoroSynthesisAudioUnit: Playback complete")
            }

            return noErr
        }
    }

    // MARK: - Audio Buffer Creation

    /// Create an AVAudioPCMBuffer from Float32 samples
    private func createAudioBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.sampleRate,
            channels: AVAudioChannelCount(Constants.channelCount),
            interleaved: false
        ) else {
            print("KokoroSynthesisAudioUnit: Failed to create audio format")
            return nil
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("KokoroSynthesisAudioUnit: Failed to create PCM buffer")
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
}

// MARK: - Factory Function

/// Factory class for creating KokoroSynthesisAudioUnit instances
/// This is referenced in the extension's Info.plist
@available(macOS 13.0, iOS 16.0, *)
@objc
public class KokoroSynthesisAudioUnitFactory: NSObject, AUAudioUnitFactory {

    /// Required by AUAudioUnitFactory protocol
    /// Creates audio unit instances when requested by the system
    @objc
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        return try KokoroSynthesisAudioUnit(componentDescription: componentDescription)
    }

    /// Required by NSExtensionRequestHandling protocol (inherited through AUAudioUnitFactory)
    @objc
    public func beginRequest(with context: NSExtensionContext) {
        // Audio Unit extensions don't use this method directly
        // The system uses createAudioUnit(with:) instead
    }
}

// MARK: - Audio Unit View Controller (Optional)

#if os(macOS) && canImport(CoreAudioKit)
/// Optional view controller for the audio unit
/// Can be used for debugging or configuration UI
@available(macOS 13.0, *)
public class KokoroSynthesisAudioUnitViewController: AUViewController {

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Add minimal UI for debugging if needed
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
#endif
