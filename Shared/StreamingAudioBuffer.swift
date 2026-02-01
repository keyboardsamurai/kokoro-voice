// Shared/StreamingAudioBuffer.swift
// KokoroVoice
//
// Thread-safe streaming audio buffer optimized for real-time audio.
// Uses os_unfair_lock for real-time safety and ring buffer for O(1) operations.

import Foundation
import os
import AVFoundation
import Accelerate

/// Thread-safe streaming audio buffer for real-time audio synthesis
///
/// Design principles:
/// - os_unfair_lock for real-time safety (never held across await)
/// - Lock held only for index/pointer bookkeeping, not sample copying
/// - Ring buffer for O(1) chunk enqueue/dequeue
/// - Virtual silence chunks to avoid memory allocation for pauses
public final class StreamingAudioBuffer: @unchecked Sendable {

    // MARK: - Types

    /// Audio chunk - either real samples or virtual silence
    public enum AudioChunk {
        case audio([Float])           // Actual audio samples
        case silence(frameCount: Int) // Virtual silence - no memory allocated

        var frameCount: Int {
            switch self {
            case .audio(let samples): return samples.count
            case .silence(let count): return count
            }
        }

        var isSilence: Bool {
            switch self {
            case .audio: return false
            case .silence: return true
            }
        }
    }

    /// Result from readFrames operation
    public struct ReadResult {
        public let framesRead: AVAudioFrameCount
        public let isComplete: Bool
        public let hadError: Bool
        public let wasSpeech: Bool  // True if any frames came from .audio chunk
    }

    // MARK: - Constants

    /// Maximum buffered frames before backpressure (10 seconds at 24kHz)
    public static let maxBufferedFrames: AVAudioFramePosition = 24000 * 10

    /// Minimum buffer before starting playback (250ms at 24kHz)
    public static let minBufferBeforeStart: AVAudioFramePosition = 24000 / 4

    /// Maximum pause duration in seconds (DoS protection)
    public static let maxPauseDuration: Float = 30.0

    /// Maximum number of segments (ring capacity must exceed this)
    public static let maxSegments = 1000

    /// Ring buffer capacity - must be > maxSegments for invariant
    private static let ringCapacity = 1024

    // MARK: - Properties

    private var lock = os_unfair_lock()

    // Ring buffer for chunks
    private var chunkRing: [AudioChunk?]
    private var ringHead: Int = 0  // Next slot to read
    private var ringTail: Int = 0  // Next slot to write
    private var ringCount: Int = 0 // Current number of chunks

    // Position within current chunk
    private var frameOffsetInCurrentChunk: Int = 0

    // State tracking
    private var synthesisComplete = false
    private var synthesisError: Error?
    private var totalFramesEnqueued: AVAudioFramePosition = 0
    private var totalFramesRead: AVAudioFramePosition = 0
    private var isReset = false

    // Rate-limited logging for segment limit
    private var hasLoggedSegmentLimit = false

    // MARK: - Initialization

    public init() {
        // Pre-allocate ring buffer
        self.chunkRing = [AudioChunk?](repeating: nil, count: Self.ringCapacity)
    }

    // MARK: - Producer Methods (Synthesis Task)

    /// Enqueue a new chunk. Uses polling for backpressure (never holds lock across await).
    /// Returns false if buffer was reset (caller should stop synthesis).
    public func enqueue(_ chunk: AudioChunk) async -> Bool {
        // Check segment limit BEFORE backpressure polling
        let (currentCount, wasReset) = withLock { (ringCount, isReset) }

        if wasReset { return false }

        if currentCount >= Self.maxSegments {
            if !hasLoggedSegmentLimit {
                print("StreamingAudioBuffer: Segment limit (\(Self.maxSegments)) reached, excess dropped")
                hasLoggedSegmentLimit = true
            }
            return true  // Don't stop synthesis, just drop excess
        }

        // Poll for buffer space based on frame count
        while true {
            let (shouldWait, resetFlag) = withLock {
                if isReset { return (false, true) }
                let buffered = totalFramesEnqueued - totalFramesRead
                return (buffered >= Self.maxBufferedFrames, false)
            }

            if resetFlag { return false }
            if !shouldWait { break }

            // Wait outside the lock, then re-check
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Now enqueue with lock held briefly
        let enqueued = withLock { () -> Bool in
            guard !isReset else { return false }
            guard ringCount < Self.ringCapacity else { return false }

            // Ring enqueue
            chunkRing[ringTail] = chunk
            ringTail = (ringTail + 1) % Self.ringCapacity
            ringCount += 1
            totalFramesEnqueued += AVAudioFramePosition(chunk.frameCount)
            return true
        }

        return enqueued
    }

    /// Mark synthesis as complete (success)
    public func markComplete() {
        withLock { synthesisComplete = true }
    }

    /// Mark synthesis as failed - remaining audio will play, then error signaled
    public func markFailed(error: Error) {
        withLock {
            synthesisComplete = true
            synthesisError = error
        }
    }

    // MARK: - Consumer Methods (Render Thread)

    /// Read frames into output buffer. NEVER BLOCKS.
    ///
    /// Returns ReadResult with:
    /// - framesRead: Number of frames copied (may be 0 if underrun)
    /// - isComplete: True when synthesis done AND buffer fully consumed
    /// - hadError: True if synthesis failed (only valid when isComplete)
    /// - wasSpeech: True if any frames came from .audio chunk
    ///
    /// Behavior by state:
    /// - Buffer has data: Copy frames, return count
    /// - Buffer empty, synthesis ongoing: Return 0 frames (underrun - caller fills silence)
    /// - Buffer empty, synthesis complete: Return isComplete=true
    /// - Buffer was reset: Return isComplete=true immediately
    public func readFrames(
        into output: UnsafeMutablePointer<Float32>,
        count: AVAudioFrameCount
    ) -> ReadResult {
        // Phase 1: Under lock - get chunk info and prepare for copy
        let readInfo = withLock { () -> ReadInfo in
            // Handle reset state
            if isReset {
                return ReadInfo(isReset: true)
            }

            // Collect chunks to read
            var chunksToRead: [(chunk: AudioChunk, startOffset: Int, framesToCopy: Int)] = []
            var framesNeeded = Int(count)
            var tempOffset = frameOffsetInCurrentChunk
            var tempHead = ringHead
            var tempCount = ringCount
            var idx = 0

            while framesNeeded > 0 && tempCount > 0 {
                guard let chunk = chunkRing[tempHead] else { break }

                let remainingInChunk = chunk.frameCount - tempOffset
                let framesToCopy = min(framesNeeded, remainingInChunk)

                chunksToRead.append((chunk, tempOffset, framesToCopy))

                framesNeeded -= framesToCopy

                if framesToCopy >= remainingInChunk {
                    // Will consume this chunk
                    tempHead = (tempHead + 1) % Self.ringCapacity
                    tempCount -= 1
                    tempOffset = 0
                } else {
                    tempOffset += framesToCopy
                }

                idx += 1
            }

            return ReadInfo(
                isReset: false,
                chunksToRead: chunksToRead,
                synthesisComplete: synthesisComplete,
                synthesisError: synthesisError,
                isEmpty: ringCount == 0
            )
        }

        // Handle reset
        if readInfo.isReset {
            return ReadResult(framesRead: 0, isComplete: true, hadError: false, wasSpeech: false)
        }

        // Handle empty buffer
        if readInfo.chunksToRead.isEmpty {
            let isComplete = readInfo.synthesisComplete && readInfo.isEmpty
            let hadError = isComplete && readInfo.synthesisError != nil
            return ReadResult(framesRead: 0, isComplete: isComplete, hadError: hadError, wasSpeech: false)
        }

        // Phase 2: Outside lock - bulk copy samples
        var framesWritten: AVAudioFrameCount = 0
        var wasSpeech = false

        for (chunk, startOffset, framesToCopy) in readInfo.chunksToRead {
            switch chunk {
            case .audio(let samples):
                wasSpeech = true
                // Bulk copy using memcpy
                samples.withUnsafeBufferPointer { srcBuffer in
                    let srcPtr = srcBuffer.baseAddress! + startOffset
                    let dstPtr = output + Int(framesWritten)
                    memcpy(dstPtr, srcPtr, framesToCopy * MemoryLayout<Float>.size)
                }

            case .silence:
                // Bulk zero using vDSP_vclr
                vDSP_vclr(output + Int(framesWritten), 1, vDSP_Length(framesToCopy))
            }

            framesWritten += AVAudioFrameCount(framesToCopy)
        }

        // Phase 3: Under lock - update indices and dequeue consumed chunks
        let finalResult = withLock { () -> ReadResult in
            // Re-check reset
            if isReset {
                return ReadResult(framesRead: 0, isComplete: true, hadError: false, wasSpeech: false)
            }

            // Apply the reads we just did
            var remaining = Int(framesWritten)

            while remaining > 0 && ringCount > 0 {
                guard let chunk = chunkRing[ringHead] else { break }

                let remainingInChunk = chunk.frameCount - frameOffsetInCurrentChunk
                let framesConsumed = min(remaining, remainingInChunk)

                frameOffsetInCurrentChunk += framesConsumed
                totalFramesRead += AVAudioFramePosition(framesConsumed)
                remaining -= framesConsumed

                // Dequeue fully consumed chunk
                if frameOffsetInCurrentChunk >= chunk.frameCount {
                    chunkRing[ringHead] = nil  // Release reference
                    ringHead = (ringHead + 1) % Self.ringCapacity
                    ringCount -= 1
                    frameOffsetInCurrentChunk = 0
                }
            }

            // Determine completion state
            let isComplete = synthesisComplete && ringCount == 0
            let hadError = isComplete && synthesisError != nil

            return ReadResult(
                framesRead: framesWritten,
                isComplete: isComplete,
                hadError: hadError,
                wasSpeech: wasSpeech
            )
        }

        return finalResult
    }

    /// Check if buffer has minimum audio to start playback
    public var hasMinimumBuffer: Bool {
        withLock {
            if isReset { return false }
            if synthesisComplete { return true } // Play whatever we have
            let buffered = totalFramesEnqueued - totalFramesRead
            return buffered >= Self.minBufferBeforeStart
        }
    }

    /// Current buffered frame count (for diagnostics)
    public var bufferedFrames: AVAudioFramePosition {
        withLock { totalFramesEnqueued - totalFramesRead }
    }

    // MARK: - Control Methods

    /// Reset all state immediately (for cancellation)
    public func reset() {
        withLock {
            isReset = true
            // Clear the ring buffer
            for i in 0..<Self.ringCapacity {
                chunkRing[i] = nil
            }
            ringHead = 0
            ringTail = 0
            ringCount = 0
            frameOffsetInCurrentChunk = 0
            synthesisComplete = false
            synthesisError = nil
            totalFramesEnqueued = 0
            totalFramesRead = 0
            hasLoggedSegmentLimit = false
        }
    }

    // MARK: - Lock Helper

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
}

// MARK: - Internal Types

private struct ReadInfo {
    let isReset: Bool
    let chunksToRead: [(chunk: StreamingAudioBuffer.AudioChunk, startOffset: Int, framesToCopy: Int)]
    let synthesisComplete: Bool
    let synthesisError: Error?
    let isEmpty: Bool

    init(isReset: Bool = false,
         chunksToRead: [(chunk: StreamingAudioBuffer.AudioChunk, startOffset: Int, framesToCopy: Int)] = [],
         synthesisComplete: Bool = false,
         synthesisError: Error? = nil,
         isEmpty: Bool = true) {
        self.isReset = isReset
        self.chunksToRead = chunksToRead
        self.synthesisComplete = synthesisComplete
        self.synthesisError = synthesisError
        self.isEmpty = isEmpty
    }
}
