// KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift
// KokoroVoice
//
// Main Audio Unit class implementing AVSpeechSynthesisProviderAudioUnit
// for the Kokoro TTS Speech Synthesis Provider.
//
// Implements chunked audio streaming for low-latency playback:
// - Audio plays within ~500ms of request (TTFA target)
// - Progressive streaming while synthesis continues in background
// - Graceful degradation on buffer underrun (silence, never block)

import Foundation
import AVFoundation
import AudioToolbox
import KokoroVoiceShared
import os
import Accelerate

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

    /// Current speech request being processed
    private var currentRequest: AVSpeechSynthesisProviderRequest?

    /// Serial queue for synthesis operations (legacy mode)
    private let synthesisQueue = DispatchQueue(
        label: "com.kokorovoice.synthesis",
        qos: .userInteractive
    )

    /// Flag indicating if the model is loaded and ready
    private var isModelReady = false

    /// Pending requests queue (for when model isn't ready) - backing storage
    private var _pendingRequests: [AVSpeechSynthesisProviderRequest] = []

    // MARK: - Streaming Mode State

    /// Thread-safe state lock (RT-safe, replaces NSLock)
    private var stateLock = os_unfair_lock()

    /// Active streaming buffer (thread-safe access via stateLock)
    private var _activeStreamingBuffer: StreamingAudioBuffer?

    /// Current synthesis task (thread-safe access via stateLock)
    private var _currentSynthesisTask: Task<Void, Never>?

    /// Whether streaming mode is enabled (validated at init)
    private var useStreamingMode = true

    // MARK: - Streaming Constants

    /// Maximum SSML segments to process (DoS protection for input)
    /// Separate from buffer's maxChunks which is the internal ring buffer limit
    private static let maxSSMLSegments = 1000

    /// Maximum chunk size for oversized audio splitting (leave 10% headroom)
    /// 9 seconds at 24kHz = 216,000 frames
    private static let maxChunkSize = Int(StreamingAudioBuffer.maxBufferedFrames) * 9 / 10

    // MARK: - Legacy Mode State (Non-streaming fallback)
    // Note: Legacy variables use stateLock for thread safety (accessed from render + synthesis threads)

    /// Legacy: Current audio buffer containing synthesized speech (backing storage)
    private var _legacyBuffer: AVAudioPCMBuffer?

    /// Legacy: Current position in the audio buffer (backing storage)
    private var _legacyFramePosition: AVAudioFramePosition = 0

    /// Legacy: Flag indicating synthesis completed with empty result (backing storage)
    private var _legacySynthesisCompletedEmpty = false

    // MARK: - TTFA Tracking (DEBUG only)

    #if DEBUG
    /// Flag indicating if first speech frame has been emitted
    private var hasEmittedFirstSpeech = false

    /// Callback when first speech frame is rendered (for TTFA measurement)
    /// Must be @Sendable because it's dispatched to main queue from render thread
    public var onFirstSpeechFrame: (@Sendable () -> Void)?
    #endif

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

        // Validate format for streaming mode
        validateOutputFormat()

        // Load model asynchronously
        Task {
            await self.loadModel()
        }

        print("KokoroSynthesisAudioUnit: Initialized with format \(outputFormat), streaming=\(useStreamingMode)")
    }

    // MARK: - Format Validation

    /// Validate output format for streaming compatibility
    private func validateOutputFormat() {
        let format = _outputBusses[0].format

        let isCompatible = format.sampleRate == Constants.sampleRate &&
                           format.channelCount == 1 &&
                           format.commonFormat == .pcmFormatFloat32

        if !isCompatible {
            useStreamingMode = false
            print("KokoroSynthesisAudioUnit: Format mismatch (\(format.sampleRate)Hz, \(format.channelCount)ch), using non-streaming mode")
        }
    }

    // MARK: - Thread-Safe Accessors

    private var activeStreamingBuffer: StreamingAudioBuffer? {
        get { withStateLock { _activeStreamingBuffer } }
        set { withStateLock { _activeStreamingBuffer = newValue } }
    }

    private var currentSynthesisTask: Task<Void, Never>? {
        get { withStateLock { _currentSynthesisTask } }
        set { withStateLock { _currentSynthesisTask = newValue } }
    }

    // Thread-safe accessors for legacy state
    private var legacyBuffer: AVAudioPCMBuffer? {
        get { withStateLock { _legacyBuffer } }
        set { withStateLock { _legacyBuffer = newValue } }
    }

    private var legacyFramePosition: AVAudioFramePosition {
        get { withStateLock { _legacyFramePosition } }
        set { withStateLock { _legacyFramePosition = newValue } }
    }

    private var legacySynthesisCompletedEmpty: Bool {
        get { withStateLock { _legacySynthesisCompletedEmpty } }
        set { withStateLock { _legacySynthesisCompletedEmpty = newValue } }
    }

    // Thread-safe operations for pending requests
    private func appendPendingRequest(_ request: AVSpeechSynthesisProviderRequest) {
        withStateLock { _pendingRequests.append(request) }
    }

    private func takePendingRequests() -> [AVSpeechSynthesisProviderRequest] {
        withStateLock {
            let requests = _pendingRequests
            _pendingRequests.removeAll()
            return requests
        }
    }

    private func clearPendingRequests() {
        withStateLock { _pendingRequests.removeAll() }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return body()
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
        // Atomically take all pending requests to avoid race with new incoming requests
        let requests = takePendingRequests()

        for request in requests {
            if useStreamingMode {
                let ssml = request.ssmlRepresentation
                let voiceIdentifier = request.voice.identifier
                let segments = SSMLParser.parse(ssml)
                let voiceId = voiceIdentifier.replacingOccurrences(of: Constants.voiceIdentifierPrefix, with: "")

                let buffer = StreamingAudioBuffer()
                activeStreamingBuffer = buffer
                await synthesizeSegmentsStreaming(segments, voiceId: voiceId, into: buffer)
            } else {
                let ssml = request.ssmlRepresentation
                let voiceIdentifier = request.voice.identifier
                await performSynthesisLegacy(ssml: ssml, voiceIdentifier: voiceIdentifier)
            }
        }
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

        // Cancel any existing synthesis
        cancelCurrentSynthesis()

        // Store current request
        currentRequest = speechRequest

        #if DEBUG
        hasEmittedFirstSpeech = false
        #endif

        // If model isn't ready, queue the request
        guard isModelReady else {
            print("KokoroSynthesisAudioUnit: Model not ready, queueing request")
            appendPendingRequest(speechRequest)
            return
        }

        // Check streaming mode
        guard useStreamingMode else {
            synthesizeSpeechRequestLegacy(speechRequest)
            return
        }

        // Parse SSML
        let segments = SSMLParser.parse(speechRequest.ssmlRepresentation)
        let voiceId = speechRequest.voice.identifier.replacingOccurrences(of: Constants.voiceIdentifierPrefix, with: "")

        print("KokoroSynthesisAudioUnit: Synthesizing (streaming) for voice: \(voiceId), segments: \(segments.count)")

        // Create fresh streaming buffer
        let buffer = StreamingAudioBuffer()
        activeStreamingBuffer = buffer

        // Copy segments to ensure Sendable safety (SynthesisSegment is Equatable/value type)
        let segmentsCopy = segments

        // Start synthesis task
        let task = Task { @Sendable [weak self] in
            guard let self = self else { return }
            await self.synthesizeSegmentsStreaming(segmentsCopy, voiceId: voiceId, into: buffer)
        }
        currentSynthesisTask = task
    }

    /// Synthesize segments into streaming buffer
    private func synthesizeSegmentsStreaming(
        _ segments: [SSMLParser.SynthesisSegment],
        voiceId: String,
        into buffer: StreamingAudioBuffer
    ) async {
        do {
            var segmentCount = 0

            for segment in segments {
                // Check SSML segment limit (DoS protection)
                segmentCount += 1
                if segmentCount > Self.maxSSMLSegments {
                    print("KokoroSynthesisAudioUnit: SSML segment limit (\(Self.maxSSMLSegments)) reached, truncating")
                    break
                }

                // Check for cancellation
                try Task.checkCancellation()

                // Handle pause before segment
                if segment.pauseBefore > 0 {
                    let clampedPause = min(Float(segment.pauseBefore), StreamingAudioBuffer.maxPauseDuration)
                    let silenceFrames = Int(clampedPause * Float(Constants.sampleRate))

                    // Validate frame count
                    guard silenceFrames > 0 && silenceFrames < Int.max / 2 else {
                        continue // Skip invalid pause
                    }

                    let shouldContinue = await buffer.enqueue(.silence(frameCount: silenceFrames))
                    if !shouldContinue { return } // Buffer was reset
                }

                // Skip empty text
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                // Check for cancellation before expensive synthesis
                try Task.checkCancellation()

                // Generate audio
                let audio = try await KokoroEngine.shared.generateAudio(
                    text: text,
                    voiceId: voiceId,
                    speed: segment.rate
                )

                // Validate audio samples (replace NaN/Inf with silence)
                let validated = audio.map { sample -> Float in
                    if sample.isNaN || sample.isInfinite {
                        return 0.0
                    }
                    return sample
                }

                // Split if oversized (prevents poll-wait deadlock for huge segments)
                if validated.count > Self.maxChunkSize {
                    // Split into multiple chunks
                    var offset = 0
                    while offset < validated.count {
                        let end = min(offset + Self.maxChunkSize, validated.count)
                        let chunk = Array(validated[offset..<end])
                        let shouldContinue = await buffer.enqueue(.audio(chunk))
                        if !shouldContinue { return } // Buffer was reset
                        offset = end
                    }
                } else {
                    // Normal case: enqueue as single chunk
                    let shouldContinue = await buffer.enqueue(.audio(validated))
                    if !shouldContinue { return } // Buffer was reset
                }
            }

            buffer.markComplete()

        } catch is CancellationError {
            // Clean exit on cancellation
            print("KokoroSynthesisAudioUnit: Synthesis cancelled")
        } catch {
            print("KokoroSynthesisAudioUnit: Synthesis error: \(error)")
            buffer.markFailed(error: error)
        }
    }

    /// Cancel the current speech request
    public override func cancelSpeechRequest() {
        print("KokoroSynthesisAudioUnit: Cancelling speech request")
        cancelCurrentSynthesis()
        clearPendingRequests()
    }

    /// Cancel current synthesis (thread-safe)
    private func cancelCurrentSynthesis() {
        // Get current task/buffer and clear all state atomically
        let (task, buffer) = withStateLock { () -> (Task<Void, Never>?, StreamingAudioBuffer?) in
            let t = _currentSynthesisTask
            let b = _activeStreamingBuffer
            _currentSynthesisTask = nil
            _activeStreamingBuffer = nil
            // Also clear legacy state atomically
            _legacyBuffer = nil
            _legacyFramePosition = 0
            _legacySynthesisCompletedEmpty = false
            return (t, b)
        }

        // Cancel outside the lock
        task?.cancel()
        buffer?.reset()

        currentRequest = nil
    }

    // MARK: - Audio Rendering

    /// Internal render block that provides audio to the system
    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputAudioBufferList, _, _ in
            guard let self = self else {
                return kAudio_ParamError
            }

            // Get output buffer pointer
            let outputPtr = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            guard outputPtr.count > 0,
                  let output = outputPtr[0].mData?.assumingMemoryBound(to: Float32.self) else {
                return kAudio_ParamError
            }

            // Try streaming mode first
            if let buffer = self.activeStreamingBuffer {
                return self.renderStreaming(buffer: buffer, output: output, frameCount: frameCount, actionFlags: actionFlags)
            }

            // Fall back to legacy mode
            return self.renderLegacy(output: output, frameCount: frameCount, actionFlags: actionFlags)
        }
    }

    /// Render using streaming buffer
    private func renderStreaming(
        buffer: StreamingAudioBuffer,
        output: UnsafeMutablePointer<Float32>,
        frameCount: AVAudioFrameCount,
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>
    ) -> OSStatus {
        // Wait for minimum buffer before starting playback
        guard buffer.hasMinimumBuffer else {
            vDSP_vclr(output, 1, vDSP_Length(frameCount))
            return noErr
        }

        // Read frames from streaming buffer (never blocks)
        let result = buffer.readFrames(into: output, count: frameCount)

        // Fill remainder with silence if underrun
        if result.framesRead < frameCount {
            let remaining = frameCount - result.framesRead
            vDSP_vclr(output + Int(result.framesRead), 1, vDSP_Length(remaining))
        }

        // TTFA tracking (RT-safe: set flag, dispatch callback off RT thread)
        #if DEBUG
        if result.wasSpeech && !self.hasEmittedFirstSpeech {
            self.hasEmittedFirstSpeech = true
            if let callback = self.onFirstSpeechFrame {
                // Capture callback in a Sendable wrapper for dispatch
                let callbackCopy = callback
                DispatchQueue.main.async { @Sendable in
                    callbackCopy()
                }
            }
        }
        #endif

        // Signal completion when synthesis done AND buffer empty
        if result.isComplete {
            actionFlags.pointee = .offlineUnitRenderAction_Complete

            if result.hadError {
                print("KokoroSynthesisAudioUnit: Completed with synthesis error")
            } else {
                print("KokoroSynthesisAudioUnit: Streaming playback complete")
            }

            // Clean up reference
            self.activeStreamingBuffer = nil
        }

        return noErr
    }

    /// Render using legacy buffer (non-streaming fallback)
    /// Note: Batches lock acquisitions to minimize RT thread contention
    private func renderLegacy(
        output: UnsafeMutablePointer<Float32>,
        frameCount: AVAudioFrameCount,
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>
    ) -> OSStatus {
        // Phase 1: Read all state in single lock acquisition
        let (buffer, framePos, completedEmpty) = withStateLock {
            (_legacyBuffer, _legacyFramePosition, _legacySynthesisCompletedEmpty)
        }

        // Check if synthesis completed with empty result
        if completedEmpty {
            vDSP_vclr(output, 1, vDSP_Length(frameCount))
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            withStateLock { _legacySynthesisCompletedEmpty = false }
            print("KokoroSynthesisAudioUnit: Empty synthesis complete (legacy)")
            return noErr
        }

        // Check if we have audio to output
        guard let buffer = buffer,
              let sourceChannelData = buffer.floatChannelData?[0] else {
            // No audio ready - output silence
            vDSP_vclr(output, 1, vDSP_Length(frameCount))
            return noErr
        }

        let bufferLength = AVAudioFramePosition(buffer.frameLength)

        // Calculate frames to copy
        let framesRemaining = bufferLength - framePos
        let framesToCopy = min(AVAudioFramePosition(frameCount), framesRemaining)

        // Phase 2: Bulk copy OUTSIDE the lock (RT-safe)
        if framesToCopy > 0 {
            let srcPtr = sourceChannelData + Int(framePos)
            memcpy(output, srcPtr, Int(framesToCopy) * MemoryLayout<Float>.size)
        }

        // Fill remainder with silence
        if framesToCopy < frameCount {
            let remaining = UInt32(frameCount) - UInt32(framesToCopy)
            vDSP_vclr(output + Int(framesToCopy), 1, vDSP_Length(remaining))
        }

        // Phase 3: Update position and check completion in single lock
        let newFramePos = framePos + framesToCopy
        let isComplete = newFramePos >= bufferLength

        withStateLock {
            _legacyFramePosition = newFramePos
            if isComplete {
                _legacyBuffer = nil
                _legacyFramePosition = 0
            }
        }

        if isComplete {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            print("KokoroSynthesisAudioUnit: Playback complete (legacy)")
        }

        return noErr
    }

    // MARK: - Legacy Synthesis (Non-streaming fallback)

    /// Handle synthesis request in legacy (non-streaming) mode
    private func synthesizeSpeechRequestLegacy(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        print("KokoroSynthesisAudioUnit: Using legacy synthesis mode")

        // Reset buffer state atomically
        withStateLock {
            _legacyBuffer = nil
            _legacyFramePosition = 0
            _legacySynthesisCompletedEmpty = false
        }

        // Extract data from request
        let ssml = speechRequest.ssmlRepresentation
        let voiceIdentifier = speechRequest.voice.identifier

        // Process synthesis using dispatch queue
        synthesisQueue.async { [self] in
            Task {
                await self.performSynthesisLegacy(ssml: ssml, voiceIdentifier: voiceIdentifier)
            }
        }
    }

    /// Perform the actual speech synthesis (legacy mode)
    private func performSynthesisLegacy(ssml: String, voiceIdentifier: String) async {
        // Parse SSML
        let segments = SSMLParser.parse(ssml)

        // Extract voice ID from identifier
        let voiceId = voiceIdentifier.replacingOccurrences(of: Constants.voiceIdentifierPrefix, with: "")

        print("KokoroSynthesisAudioUnit: Synthesizing (legacy) for voice: \(voiceId)")
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

        // Handle empty result
        guard !allAudio.isEmpty else {
            print("KokoroSynthesisAudioUnit: No audio generated (legacy)")
            withStateLock { _legacySynthesisCompletedEmpty = true }
            return
        }

        // Create audio buffer
        let buffer = createAudioBuffer(from: allAudio)

        // Update buffer atomically
        withStateLock {
            _legacyBuffer = buffer
            _legacyFramePosition = 0
        }

        print("KokoroSynthesisAudioUnit: Audio buffer ready (legacy), \(allAudio.count) samples")
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
            // Bulk copy
            samples.withUnsafeBufferPointer { srcPtr in
                _ = memcpy(channelData, srcPtr.baseAddress!, samples.count * MemoryLayout<Float>.size)
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
