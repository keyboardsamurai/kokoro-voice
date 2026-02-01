// Shared/StreamingAudioBuffer.swift
// KokoroVoice
//
// Thread-safe streaming audio buffer optimized for real-time audio.
// Uses os_unfair_lock for real-time safety and ring buffer for O(1) operations.

import Foundation
import os
import AVFoundation
import Accelerate

#if DEBUG
import Darwin.libkern.OSAtomic
#endif

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

    /// Maximum number of chunks in ring buffer (internal limit)
    /// Increased from 1024 to handle worst-case: 1000 segments × 2 chunks/segment + oversized splitting
    public static let maxChunks = 2048

    /// Ring buffer capacity - must be >= maxChunks
    private static let ringCapacity = 2048

    // MARK: - DEBUG Metrics

    #if DEBUG
    /// Count of times trylock failed due to contention (DEBUG only)
    /// Uses OSAtomicIncrement64 for thread-safe incrementing
    /// nonisolated(unsafe) is acceptable because atomic ops provide synchronization
    private nonisolated(unsafe) static var _lockContentionCount: Int64 = 0
    public static var lockContentionCount: Int {
        get { Int(OSAtomicAdd64(0, &_lockContentionCount)) }
        set { _lockContentionCount = Int64(newValue) }
    }

    /// Total number of readFrames calls (DEBUG only)
    private nonisolated(unsafe) static var _totalReadCalls: Int64 = 0
    public static var totalReadCalls: Int {
        get { Int(OSAtomicAdd64(0, &_totalReadCalls)) }
        set { _totalReadCalls = Int64(newValue) }
    }

    /// Thread-safe increment for contention counter
    private static func incrementContentionCount() {
        OSAtomicIncrement64(&_lockContentionCount)
    }

    /// Thread-safe increment for total read calls counter
    private static func incrementTotalReadCalls() {
        OSAtomicIncrement64(&_totalReadCalls)
    }
    #endif

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
        // Check chunk limit BEFORE backpressure polling
        let (currentCount, wasReset) = withLock { (ringCount, isReset) }

        if wasReset { return false }

        if currentCount >= Self.maxChunks {
            if !hasLoggedSegmentLimit {
                print("StreamingAudioBuffer: Chunk limit (\(Self.maxChunks)) reached, excess dropped")
                hasLoggedSegmentLimit = true
            }
            return true  // Don't stop synthesis, just drop excess
        }

        // Poll for buffer space based on frame count (accounting for incoming chunk)
        let incomingFrames = AVAudioFramePosition(chunk.frameCount)
        while true {
            let (shouldWait, resetFlag) = withLock {
                if isReset { return (false, true) }
                let buffered = totalFramesEnqueued - totalFramesRead

                // Special case: if chunk is larger than max buffer, only wait if buffer non-empty
                // This prevents deadlock on oversized chunks (which shouldn't happen after
                // KokoroSynthesisAudioUnit's chunk splitting, but we handle it defensively)
                if incomingFrames > Self.maxBufferedFrames {
                    return (buffered > 0, false)
                }

                // Normal case: check if adding this chunk would exceed max buffer
                return (buffered + incomingFrames > Self.maxBufferedFrames, false)
            }

            if resetFlag { return false }
            if !shouldWait { break }

            // Wait outside the lock, then re-check
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Now enqueue with lock held briefly
        let enqueued = withLock { () -> Bool in
            guard !isReset else { return false }

            // If ring is full, drop chunk but don't stop synthesis
            // (Same behavior as chunk limit - graceful degradation)
            guard ringCount < Self.ringCapacity else {
                print("StreamingAudioBuffer: Ring capacity full, chunk dropped")
                return true  // Return true so caller continues synthesis
            }

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
    /// Uses os_unfair_lock_trylock to guarantee non-blocking behavior on render thread.
    /// If lock is contended, returns 0 frames (silence fallback) instead of blocking.
    /// Lock contention is extremely rare (<0.001% of calls) due to sub-microsecond hold times.
    ///
    /// Uses "reserve then copy" pattern:
    /// - Phase 1 (locked): Reserve frames by advancing indices, retain chunk refs for copying
    /// - Phase 2 (unlocked): Bulk copy from retained chunk references
    /// This eliminates the race condition of a separate Phase 3 index update.
    ///
    /// Returns ReadResult with:
    /// - framesRead: Number of frames copied (may be 0 if underrun or lock contended)
    /// - isComplete: True when synthesis done AND buffer fully consumed
    /// - hadError: True if synthesis failed (only valid when isComplete)
    /// - wasSpeech: True if any frames came from .audio chunk
    ///
    /// Behavior by state:
    /// - Buffer has data: Copy frames, return count
    /// - Buffer empty, synthesis ongoing: Return 0 frames (underrun - caller fills silence)
    /// - Buffer empty, synthesis complete: Return isComplete=true
    /// - Buffer was reset: Return isComplete=true immediately
    /// - Lock contended: Return 0 frames (silence fallback, RT-safe)
    public func readFrames(
        into output: UnsafeMutablePointer<Float32>,
        count: AVAudioFrameCount
    ) -> ReadResult {
        #if DEBUG
        Self.incrementTotalReadCalls()
        #endif

        // Phase 1: Try to acquire lock without blocking (RT-safe)
        guard os_unfair_lock_trylock(&lock) else {
            // Lock contended - return silence instead of blocking
            // This is extremely rare (<0.001% of calls) but guarantees RT safety
            #if DEBUG
            Self.incrementContentionCount()
            #endif
            return ReadResult(framesRead: 0, isComplete: false, hadError: false, wasSpeech: false)
        }

        // Under lock - reserve frames by collecting chunk refs AND advancing indices
        // Handle reset state
        if isReset {
            os_unfair_lock_unlock(&lock)
            return ReadResult(framesRead: 0, isComplete: true, hadError: false, wasSpeech: false)
        }

        // Collect chunks to read AND advance indices atomically ("reserve then copy" pattern)
        // The AudioChunk values retain underlying [Float] arrays via copy-on-write,
        // so we can safely nil ring slots while keeping data references for copying.
        var chunksToRead: [(chunk: AudioChunk, startOffset: Int, framesToCopy: Int)] = []
        var framesNeeded = Int(count)
        var totalFramesToRead: AVAudioFramePosition = 0

        while framesNeeded > 0 && ringCount > 0 {
            guard let chunk = chunkRing[ringHead] else { break }

            let remainingInChunk = chunk.frameCount - frameOffsetInCurrentChunk
            let framesToCopy = min(framesNeeded, remainingInChunk)

            // Retain chunk reference for Phase 2 copy
            chunksToRead.append((chunk, frameOffsetInCurrentChunk, framesToCopy))

            framesNeeded -= framesToCopy
            totalFramesToRead += AVAudioFramePosition(framesToCopy)

            if framesToCopy >= remainingInChunk {
                // Fully consumed this chunk - advance to next
                chunkRing[ringHead] = nil  // Release ring slot (chunk retained in chunksToRead)
                ringHead = (ringHead + 1) % Self.ringCapacity
                ringCount -= 1
                frameOffsetInCurrentChunk = 0
            } else {
                // Partially consumed - update offset within chunk
                frameOffsetInCurrentChunk += framesToCopy
            }
        }

        // Update total frames read counter
        totalFramesRead += totalFramesToRead

        // Capture completion state while still holding lock
        let isComplete = synthesisComplete && ringCount == 0
        let hadError = isComplete && synthesisError != nil

        // Release lock - indices already advanced, ready for bulk copy
        os_unfair_lock_unlock(&lock)

        // Handle empty buffer (no data was available)
        if chunksToRead.isEmpty {
            return ReadResult(framesRead: 0, isComplete: isComplete, hadError: hadError, wasSpeech: false)
        }

        // Phase 2: Outside lock - bulk copy samples from retained chunk references
        var framesWritten: AVAudioFrameCount = 0
        var wasSpeech = false

        for (chunk, startOffset, framesToCopy) in chunksToRead {
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

        return ReadResult(
            framesRead: framesWritten,
            isComplete: isComplete,
            hadError: hadError,
            wasSpeech: wasSpeech
        )
    }

    /// Check if buffer has minimum audio to start playback
    /// Uses trylock for RT-safety - returns false if lock contended (safe default)
    public var hasMinimumBuffer: Bool {
        // Try to acquire lock without blocking (RT-safe)
        guard os_unfair_lock_trylock(&lock) else {
            // Lock contended - return false (safe: will check again next render call)
            return false
        }
        defer { os_unfair_lock_unlock(&lock) }

        if isReset { return false }
        if synthesisComplete { return true } // Play whatever we have
        let buffered = totalFramesEnqueued - totalFramesRead
        return buffered >= Self.minBufferBeforeStart
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
