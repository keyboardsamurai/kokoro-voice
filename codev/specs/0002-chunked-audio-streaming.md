# Spec 0002: Chunked Audio Streaming

## Status
**specified** - Approved 2025-01-31

## Problem Statement

Currently, `KokoroSynthesisAudioUnit` synthesizes the entire audio buffer before playback begins:

```swift
// Current implementation (KokoroSynthesisAudioUnit.swift:250-298)
var allAudio: [Float] = []
for segment in segments {
    let audio = try await KokoroEngine.shared.generateAudio(...)
    allAudio.append(contentsOf: audio)  // Accumulates ALL audio
}
// Only after ALL segments complete:
let buffer = createAudioBuffer(from: allAudio)
currentBuffer = buffer  // NOW playback can begin
```

**Impact:** For longer text, users wait with no audio feedback. A 30-second speech takes 5-10+ seconds before any sound plays. This kills perceived performance even if total synthesis time is acceptable.

## Goals

1. **First audio in <500ms** - User hears audio within 500ms of request (see Definitions for caveats)
2. **Progressive streaming** - Audio plays continuously while synthesis continues in background
3. **Seamless playback** - No stuttering or gaps between chunks (unless original text has pauses)
4. **Graceful degradation** - If synthesis can't keep up with playback, insert silence (never block)

## Definitions

### Time to First Audio (TTFA)

**Definition:** The time from `synthesizeSpeechRequest()` being called to the first non-silence audio frame being rendered to the output buffer.

**Measurement:** Capture timestamp at start of `synthesizeSpeechRequest()`. Capture timestamp when `readFrames()` first returns frames from actual speech audio (not silence or pause segments). Difference is TTFA.

**Caveats:**
- If the first SSML segment is a `<break>` or pause, TTFA is measured from first *speech* audio, not the silence.
- If the first text segment itself requires >500ms to synthesize (very long sentence), TTFA will exceed 500ms. This is acceptable - the guarantee is "as fast as possible given segment boundaries."
- Future enhancement: Pre-chunk long first segments at clause boundaries to maintain <500ms even for long sentences.

### Graceful Degradation

When synthesis cannot keep up with playback (buffer underrun):
- **Behavior:** Insert silence frames - never block, never pause, never time-stretch
- **Timeline:** Silence is part of the output timeline (not "caught up" later)
- **UX:** Brief silence is preferable to stuttering or blocking the audio system

## Non-Goals

- Changing the KokoroEngine API (it remains synchronous per-segment)
- Real-time streaming from network (this is local synthesis)
- Sub-sentence chunking (SSML segment boundaries are natural chunk points) - deferred to future spec
- Parallel segment synthesis (segments must be sequential to maintain audio order)

## User Guidance

For optimal latency with long texts, users should structure SSML with natural breaks:
- Use `<s>` tags around sentences
- Use `<p>` tags around paragraphs
- Avoid single segments longer than ~50 words

This guidance should be documented in user-facing documentation (not enforced in code).

## Technical Design

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    KokoroSynthesisAudioUnit                      │
│                                                                  │
│  ┌──────────────────┐     ┌─────────────────────────────────┐  │
│  │  Synthesis Task  │────▶│     StreamingAudioBuffer         │  │
│  │  (async loop)    │     │  ┌─────┬─────┬─────┬─────┐      │  │
│  │                  │     │  │ C1  │ C2  │ C3  │ ... │      │  │
│  │  for segment in  │     │  └─────┴─────┴─────┴─────┘      │  │
│  │    segments:     │     │       ▲               │          │  │
│  │    generate()    │     │  write │          read │          │  │
│  │    enqueue()     │     │       │               ▼          │  │
│  └──────────────────┘     │  ┌─────────────────────────┐    │  │
│                           │  │   internalRenderBlock   │    │  │
│                           │  │   (consumes frames)     │    │  │
│                           │  └─────────────────────────┘    │  │
│                           └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. StreamingAudioBuffer

A thread-safe buffer using `os_unfair_lock` for real-time audio thread safety.

**Critical design constraint:** The lock is NEVER held across an `await`. All lock acquisitions are synchronous, sub-microsecond operations.

```swift
import os

/// Thread-safe buffer for streaming audio chunks
/// Uses os_unfair_lock for real-time audio thread compatibility
final class StreamingAudioBuffer: @unchecked Sendable {
    private var lock = os_unfair_lock()

    // Chunk queue - consumed chunks are removed to prevent memory growth
    private var chunks: [AudioChunk] = []
    private var frameOffsetInCurrentChunk: AVAudioFrameCount = 0

    // State tracking
    private var synthesisComplete = false
    private var synthesisError: Error? = nil
    private var totalFramesEnqueued: AVAudioFramePosition = 0
    private var totalFramesRead: AVAudioFramePosition = 0
    private var isReset = false

    // Buffer limits
    static let maxBufferedFrames: AVAudioFramePosition = 24000 * 10  // 10 seconds at 24kHz
    static let minBufferBeforeStart: AVAudioFramePosition = 24000 / 4  // 250ms minimum
    static let maxPauseDuration: Float = 30.0  // Max 30 seconds for any single pause

    /// Audio chunk - either real samples or virtual silence
    enum AudioChunk {
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

    // MARK: - Producer Methods (Synthesis Task)

    /// Enqueue a new chunk. Uses polling for backpressure (never holds lock across await).
    /// Returns false if buffer was reset (caller should stop synthesis).
    func enqueue(_ chunk: AudioChunk) async -> Bool {
        // Poll for buffer space - never hold lock across await
        while true {
            let (shouldWait, wasReset) = withLock {
                if isReset { return (false, true) }
                let buffered = totalFramesEnqueued - totalFramesRead
                return (buffered >= Self.maxBufferedFrames, false)
            }

            if wasReset { return false }
            if !shouldWait { break }

            // Wait outside the lock, then re-check
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Now enqueue with lock held briefly
        withLock {
            guard !isReset else { return }
            chunks.append(chunk)
            totalFramesEnqueued += AVAudioFramePosition(chunk.frameCount)
        }
        return true
    }

    /// Mark synthesis as complete (success)
    func markComplete() {
        withLock { synthesisComplete = true }
    }

    /// Mark synthesis as failed - remaining audio will play, then error signaled
    func markFailed(error: Error) {
        withLock {
            synthesisComplete = true
            synthesisError = error
        }
    }

    // MARK: - Consumer Methods (Render Thread)

    /// Read frames into output buffer. NEVER BLOCKS.
    ///
    /// Returns:
    /// - framesRead: Number of frames copied (may be 0 if underrun)
    /// - isComplete: True when synthesis done AND buffer fully consumed
    /// - hadError: True if synthesis failed (only valid when isComplete)
    ///
    /// Behavior by state:
    /// - Buffer has data: Copy frames, return count
    /// - Buffer empty, synthesis ongoing: Return 0 frames (underrun - caller fills silence)
    /// - Buffer empty, synthesis complete: Return isComplete=true
    /// - Buffer was reset: Return isComplete=true immediately
    func readFrames(
        into output: UnsafeMutablePointer<Float32>,
        count: AVAudioFrameCount
    ) -> (framesRead: AVAudioFrameCount, isComplete: Bool, hadError: Bool) {
        withLock {
            // Handle reset state
            if isReset {
                return (0, true, false)
            }

            var framesWritten: AVAudioFrameCount = 0
            var frameIndex = 0

            while framesWritten < count && !chunks.isEmpty {
                let chunk = chunks[0]
                let chunkFrames = chunk.frameCount
                let remainingInChunk = chunkFrames - Int(frameOffsetInCurrentChunk)
                let framesToCopy = min(Int(count - framesWritten), remainingInChunk)

                switch chunk {
                case .audio(let samples):
                    // Copy actual audio samples
                    for i in 0..<framesToCopy {
                        output[Int(framesWritten) + i] = samples[Int(frameOffsetInCurrentChunk) + i]
                    }
                case .silence:
                    // Write zeros for virtual silence
                    for i in 0..<framesToCopy {
                        output[Int(framesWritten) + i] = 0.0
                    }
                }

                framesWritten += AVAudioFrameCount(framesToCopy)
                frameOffsetInCurrentChunk += AVAudioFrameCount(framesToCopy)
                totalFramesRead += AVAudioFramePosition(framesToCopy)

                // Dequeue fully consumed chunk
                if frameOffsetInCurrentChunk >= chunkFrames {
                    chunks.removeFirst()
                    frameOffsetInCurrentChunk = 0
                }
            }

            // Determine completion state
            let isComplete = synthesisComplete && chunks.isEmpty
            let hadError = isComplete && synthesisError != nil

            return (framesWritten, isComplete, hadError)
        }
    }

    /// Check if buffer has minimum audio to start playback
    var hasMinimumBuffer: Bool {
        withLock {
            if isReset { return false }
            if synthesisComplete { return true } // Play whatever we have
            let buffered = totalFramesEnqueued - totalFramesRead
            return buffered >= Self.minBufferBeforeStart
        }
    }

    /// Current buffered frame count (for diagnostics)
    var bufferedFrames: AVAudioFramePosition {
        withLock { totalFramesEnqueued - totalFramesRead }
    }

    // MARK: - Control Methods

    /// Reset all state immediately (for cancellation)
    func reset() {
        withLock {
            isReset = true
            chunks.removeAll()
            frameOffsetInCurrentChunk = 0
            synthesisComplete = false
            synthesisError = nil
            totalFramesEnqueued = 0
            totalFramesRead = 0
        }
    }

    // MARK: - Lock Helper

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
}
```

**Key Design Decisions:**

1. **Virtual silence chunks:** `AudioChunk.silence(frameCount:)` stores only frame count, not allocated samples. A 30-second pause uses 8 bytes, not 2.8MB.

2. **Polling backpressure:** `enqueue()` polls with `Task.sleep()` when buffer is full. Lock is released before sleeping - never held across `await`.

3. **Reset flag:** When `reset()` is called, `isReset` flag is set. All methods check this and exit gracefully, preventing races during cancellation.

4. **Explicit dequeue:** Chunks are removed from array when fully consumed, ensuring bounded memory.

#### 2. Audio Format Contract

The streaming buffer operates on raw `[Float]` samples with these invariants:

- **Sample rate:** 24000 Hz (from `Constants.sampleRate`)
- **Format:** Float32, mono, non-interleaved
- **Validation:** At Audio Unit initialization, validate format. If mismatch, set flag to use non-streaming fallback.

```swift
// In KokoroSynthesisAudioUnit
private var useStreamingMode = true

private func validateOutputFormat() {
    guard let format = _outputBusses[0].format else {
        useStreamingMode = false
        return
    }
    useStreamingMode = format.sampleRate == Constants.sampleRate &&
                       format.channelCount == 1 &&
                       format.commonFormat == .pcmFormatFloat32

    if !useStreamingMode {
        print("KokoroSynthesisAudioUnit: Format mismatch, using non-streaming mode")
    }
}
```

Format validation happens once at init. Mid-run format changes are not possible in this Audio Unit architecture.

#### 3. State Synchronization

All shared state between threads uses a single lock (`stateLock`) for simplicity and correctness:

```swift
// In KokoroSynthesisAudioUnit
private var stateLock = os_unfair_lock()
private var _activeStreamingBuffer: StreamingAudioBuffer?
private var _currentSynthesisTask: Task<Void, Never>?

// Thread-safe accessors
private var activeStreamingBuffer: StreamingAudioBuffer? {
    get { withStateLock { _activeStreamingBuffer } }
    set { withStateLock { _activeStreamingBuffer = newValue } }
}

private var currentSynthesisTask: Task<Void, Never>? {
    get { withStateLock { _currentSynthesisTask } }
    set { withStateLock { _currentSynthesisTask = newValue } }
}

private func withStateLock<T>(_ body: () -> T) -> T {
    os_unfair_lock_lock(&stateLock)
    defer { os_unfair_lock_unlock(&stateLock) }
    return body()
}
```

**Why one lock:** Simpler to reason about than multiple locks. Critical sections are tiny (pointer read/write), so contention is negligible.

#### 4. Modified Synthesis Flow

```swift
func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
    // Cancel any existing synthesis (thread-safe)
    cancelCurrentSynthesis()

    // Check streaming mode
    guard useStreamingMode else {
        // Fall back to existing non-streaming implementation
        synthesizeSpeechRequestNonStreaming(request)
        return
    }

    // Create fresh streaming buffer
    let streamingBuffer = StreamingAudioBuffer()

    // Store buffer reference (thread-safe)
    activeStreamingBuffer = streamingBuffer

    // Create and store task (thread-safe)
    let task = Task { [weak self] in
        guard let self = self else { return }

        do {
            for segment in segments {
                // Check for cancellation
                try Task.checkCancellation()

                // Handle pause segments with validation
                if segment.pauseBefore > 0 {
                    let clampedPause = min(segment.pauseBefore, StreamingAudioBuffer.maxPauseDuration)
                    let silenceFrames = Int(clampedPause * Float(Constants.sampleRate))

                    // Validate frame count (protect against overflow/negative)
                    guard silenceFrames > 0 && silenceFrames < Int.max / 2 else {
                        continue // Skip invalid pause
                    }

                    let shouldContinue = await streamingBuffer.enqueue(.silence(frameCount: silenceFrames))
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

                // Validate audio samples (reject NaN/Inf)
                let validatedAudio = audio.map { sample -> Float in
                    if sample.isNaN || sample.isInfinite {
                        return 0.0
                    }
                    return sample
                }

                let shouldContinue = await streamingBuffer.enqueue(.audio(validatedAudio))
                if !shouldContinue { return } // Buffer was reset
            }
            streamingBuffer.markComplete()
        } catch is CancellationError {
            // Clean exit on cancellation
        } catch {
            print("KokoroSynthesisAudioUnit: Synthesis error: \(error)")
            streamingBuffer.markFailed(error: error)
        }
    }

    currentSynthesisTask = task
}

private func cancelCurrentSynthesis() {
    // Get current task and buffer atomically
    let (task, buffer) = withStateLock { () -> (Task<Void, Never>?, StreamingAudioBuffer?) in
        let t = _currentSynthesisTask
        let b = _activeStreamingBuffer
        _currentSynthesisTask = nil
        _activeStreamingBuffer = nil
        return (t, b)
    }

    // Cancel outside the lock
    task?.cancel()
    buffer?.reset()
}
```

#### 5. Modified Render Block

```swift
var internalRenderBlock: AUInternalRenderBlock {
    return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputAudioBufferList, _, _ in
        guard let self = self else { return kAudio_ParamError }

        // Get output buffer pointer
        let outputBufferListPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        guard outputBufferListPointer.count > 0,
              let outputFrames = outputBufferListPointer[0].mData?.assumingMemoryBound(to: Float32.self) else {
            return kAudio_ParamError
        }

        // Get buffer reference (thread-safe read)
        guard let buffer = self.activeStreamingBuffer else {
            // No active request - output silence
            for i in 0..<Int(frameCount) {
                outputFrames[i] = 0.0
            }
            return noErr
        }

        // Wait for minimum buffer before starting playback
        guard buffer.hasMinimumBuffer else {
            for i in 0..<Int(frameCount) {
                outputFrames[i] = 0.0
            }
            return noErr
        }

        // Read frames from streaming buffer (never blocks)
        let (framesRead, isComplete, hadError) = buffer.readFrames(into: outputFrames, count: frameCount)

        // Fill remainder with silence if underrun
        if framesRead < frameCount {
            for i in Int(framesRead)..<Int(frameCount) {
                outputFrames[i] = 0.0
            }
        }

        // Signal completion when synthesis done AND buffer empty
        if isComplete {
            actionFlags.pointee = .offlineUnitRenderAction_Complete

            if hadError {
                print("KokoroSynthesisAudioUnit: Completed with synthesis error")
            }

            // Clean up reference
            self.activeStreamingBuffer = nil
        }

        return noErr
    }
}
```

#### 6. Cancellation Flow

```swift
public override func cancelSpeechRequest() {
    print("KokoroSynthesisAudioUnit: Cancelling speech request")

    // Cancel synthesis and reset buffer (thread-safe)
    cancelCurrentSynthesis()

    // Clear any pending requests
    pendingRequests.removeAll()
}
```

### Thread Safety Model

| Thread | Operations | Synchronization |
|--------|------------|-----------------|
| Main Thread | `synthesizeSpeechRequest`, `cancelSpeechRequest` | `stateLock` for shared state |
| Synthesis Task | `enqueue()`, `markComplete()`, `markFailed()` | Buffer's internal `os_unfair_lock` |
| Render Thread | `readFrames()`, `hasMinimumBuffer` | Buffer's internal `os_unfair_lock` |

**Critical invariants:**
1. `os_unfair_lock` critical sections are < 1μs (no allocations, no system calls, no await)
2. Render thread NEVER blocks - underrun → silence, lock contention → return immediately
3. Synthesis task may poll-wait on backpressure (acceptable, not real-time)
4. All shared pointer access goes through `stateLock`
5. Lock is NEVER held across `await`

### Completion Semantics

From the host/system perspective:

| Scenario | Completion Signal | Semantics |
|----------|-------------------|-----------|
| All segments synthesized successfully | `.offlineUnitRenderAction_Complete` | Request completed successfully |
| Synthesis error after partial audio | `.offlineUnitRenderAction_Complete` | Request completed (partial audio played) |
| All segments fail | `.offlineUnitRenderAction_Complete` | Request completed (no audio) |
| Request cancelled | No signal (buffer reset) | Request cancelled |

**Rationale:** The AVSpeechSynthesisProvider API does not have an explicit "failure" signal. We complete the request after playing whatever audio we generated. Errors are logged for debugging.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Synthesis throws mid-stream | Buffer marked failed, remaining audio plays, then completion signaled |
| Empty segments | Skipped, no chunk enqueued |
| All segments fail | Signal completion immediately (empty result) |
| Task cancelled | Buffer reset, `isReset` flag prevents further operations |
| Format mismatch at init | Use non-streaming fallback for entire session |
| NaN/Inf in audio samples | Replaced with 0.0 (silence) |
| Pause duration overflow | Clamped to 30 seconds max |
| Negative frame count | Skip the invalid pause |

### Buffer Limits

| Constant | Value | Rationale |
|----------|-------|-----------|
| `maxBufferedFrames` | 240,000 (10s) | Caps memory at ~1MB for audio chunks |
| `minBufferBeforeStart` | 6,000 (250ms) | Ensures smooth start; lower than TTFA target |
| `maxPauseDuration` | 30.0s | Prevents DoS via huge SSML pauses |

**Backpressure behavior:** When buffer reaches `maxBufferedFrames`, `enqueue()` polls every 10ms until space is available. Polling (not blocking) ensures lock is never held across await.

## Success Criteria

1. **Time to first audio**: <500ms for typical multi-segment text (measured as defined above)
2. **No regressions**: Existing SSML parsing, prosody, and voice selection work identically
3. **Smooth playback**: No audible gaps between chunks during normal operation
4. **Graceful underrun**: Buffer underrun produces silence, not crashes or audio artifacts
5. **Cancellation works**: `cancelSpeechRequest()` stops both synthesis and playback immediately
6. **Memory bounded**: Peak memory usage independent of total text length
7. **No data races**: Thread Sanitizer clean

## Testing Plan

### Unit Tests

1. **StreamingAudioBuffer**
   - Enqueue/dequeue basic flow (audio and silence chunks)
   - Virtual silence chunks use minimal memory
   - Thread safety: concurrent enqueue/read from different threads (TSan)
   - Backpressure: enqueue polls when buffer full, resumes when space available
   - Reset clears all state and stops enqueue
   - `hasMinimumBuffer` threshold behavior
   - `readFrames` returns correct values for all states (empty, partial, complete, reset)
   - Memory: consumed chunks are deallocated

2. **Synthesis flow**
   - Chunks enqueued progressively (not all at once)
   - Cancellation stops synthesis task
   - Errors propagate correctly
   - NaN/Inf samples are sanitized
   - Large pauses are clamped

3. **State synchronization**
   - `activeStreamingBuffer` access is race-free
   - `currentSynthesisTask` access is race-free
   - Concurrent cancel/synthesize calls don't crash

### Integration Tests

1. **Short text** (<1 second) - works identically to before
2. **Long text** (30+ seconds) - first audio <500ms, memory stable
3. **Cancellation mid-synthesis** - clean stop, no crashes, no leaked tasks
4. **Rapid request switching** - previous synthesis cancelled, new one starts
5. **Synthesis error mid-stream** - buffered audio plays, then completes
6. **Many tiny segments** - no excessive overhead from many chunks
7. **Single very long segment** - works, TTFA may exceed 500ms (acceptable)
8. **Huge pause in SSML** - clamped to 30s, doesn't exhaust memory
9. **Format mismatch** - falls back to non-streaming correctly

### TTFA Measurement Test

```swift
#if DEBUG
// Test-only hook - not compiled in release builds
var onFirstAudioFrame: (() -> Void)?
#endif

func testTimeToFirstAudio() async {
    let startTime = CFAbsoluteTimeGetCurrent()
    var firstAudioTime: CFAbsoluteTime?

    #if DEBUG
    audioUnit.onFirstAudioFrame = {
        if firstAudioTime == nil {
            firstAudioTime = CFAbsoluteTimeGetCurrent()
        }
    }
    #endif

    audioUnit.synthesizeSpeechRequest(longTextRequest)

    // Wait for first audio
    await waitForFirstAudio()

    let ttfa = firstAudioTime! - startTime
    XCTAssertLessThan(ttfa, 0.5, "TTFA exceeded 500ms")
}
```

### Thread Sanitizer Tests

Run all tests with Thread Sanitizer enabled to catch data races:

```bash
swift test --sanitize=thread
```

### Manual Testing

1. VoiceOver with long passages - smooth reading
2. Spoken Content with articles - no stuttering
3. Memory usage - verify stable during long synthesis (use Instruments)
4. Rapid text changes - no audio glitches or crashes

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Buffer underrun causes brief silence | Medium | Low | Accept silence; tune `minBufferBeforeStart` if needed |
| Lock contention on render thread | Low | Medium | Sub-μs critical sections; could add tryLock fallback if needed |
| Memory growth from queued chunks | Low | Medium | Explicit dequeue; `maxBufferedFrames` limit; virtual silence |
| Backpressure polling overhead | Low | Low | 10ms sleep is negligible; only occurs when buffer is full |
| DoS via huge SSML pauses | Low | Medium | `maxPauseDuration` clamp (30s) |

## Dependencies

None - this is internal to KokoroSynthesisAudioUnit.

## Files to Modify

- `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` - Main changes (~150 lines modified)
- `KokoroVoiceExtension/StreamingAudioBuffer.swift` - New file (~200 lines)
- `Tests/StreamingAudioBufferTests.swift` - New tests (~150 lines)
- `Tests/StreamingIntegrationTests.swift` - New integration tests (~100 lines)

## Estimated Scope

- **Complexity**: Medium-High
- **New code**: ~300-350 lines (StreamingAudioBuffer + tests)
- **Modified code**: ~150 lines (synthesis flow, render block, state sync)
- **Test code**: ~250 lines

## Implementation Notes

The pseudocode in this spec illustrates the design intent but requires optimization for production:

1. **Bulk copy operations:** The per-sample `for` loops in `readFrames()` must be replaced with `memcpy` or `vDSP` bulk operations. The lock should only protect index/pointer bookkeeping, not the actual sample copying.

2. **Ring buffer for chunks:** `Array.removeFirst()` is O(n). Use a ring buffer with head/tail indices, or a `ContiguousArray` with index tracking, to achieve O(1) dequeue.

3. **TTFA measurement:** The test hook needs the buffer to expose whether returned frames came from an `.audio` chunk (speech) vs `.silence` chunk. Add a `lastReadWasSpeech: Bool` output or similar.

4. **Silence in `minBufferBeforeStart`:** Currently counts all frames including silence. This is acceptable (starts playback promptly even with leading pause), but the plan should document this explicitly.

5. **Segment count limit:** Add `maxSegments = 1000` cap to prevent pathological SSML from churning chunk metadata. Log warning and truncate if exceeded.

These optimizations are deferred to the implementation plan.

## Traps to Avoid

1. **Don't use NSLock on render thread** - Causes priority inversion. Use `os_unfair_lock` exclusively.

2. **Don't block the render thread** - `internalRenderBlock` is called at audio rate (~375 times/second). Any blocking causes glitches. Underrun → silence, never wait.

3. **Don't hold lock across await** - This is undefined behavior with `os_unfair_lock`. Poll with `Task.sleep` instead.

4. **Don't use async/await in render block** - The render block is a C-style callback. Use only synchronous operations.

5. **Don't access shared state without lock** - `activeStreamingBuffer` and `currentSynthesisTask` must use `stateLock`. Plain Swift property access is not atomic.

6. **Don't leak the synthesis Task** - Store task reference and cancel explicitly. Fire-and-forget tasks cannot be cancelled.

7. **Don't forget to dequeue consumed chunks** - Keeping all chunks in memory causes unbounded growth.

8. **Don't ignore format mismatches** - If engine outputs 24kHz but AU expects 48kHz, audio plays at wrong speed. Validate and fallback.

9. **Don't allocate in the lock** - Keep `os_unfair_lock` critical sections allocation-free. Pre-allocate outside, copy pointers inside.

10. **Don't materialize silence** - A 30s pause as `[Float]` is 2.8MB. Use virtual silence chunks.

11. **Don't trust SSML input** - Validate pause durations, frame counts. Clamp to reasonable maxima.
