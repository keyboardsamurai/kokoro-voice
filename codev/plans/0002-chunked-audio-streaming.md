# Plan 0002: Chunked Audio Streaming

## Overview

**Spec:** [codev/specs/0002-chunked-audio-streaming.md](../specs/0002-chunked-audio-streaming.md)
**Status:** Draft
**Complexity:** Medium-High
**Estimated LOC:** ~500 (new) + ~150 (modified)

## Implementation Phases

### Phase 1: StreamingAudioBuffer Core
Create the thread-safe streaming buffer with real-time-safe operations.

### Phase 2: Integration with AudioUnit
Modify `KokoroSynthesisAudioUnit` to use streaming buffer.

### Phase 3: Documentation
Update user-facing docs per spec "User Guidance" section.

### Phase 4: Testing
Unit tests, integration tests, Thread Sanitizer validation.

---

## Phase 1: StreamingAudioBuffer Core

**Goal:** Implement `StreamingAudioBuffer.swift` with all optimizations from the spec's Implementation Notes.

### 1.1 File Structure

Create `Shared/StreamingAudioBuffer.swift` (in `KokoroVoiceShared` framework):

> **Why Shared?** App Extension targets (`.appex`) cannot be `@testable import`ed by test bundles. Placing in `Shared/` makes the buffer testable and consistent with `KokoroEngine` location.

```swift
import Foundation
import os
import AVFoundation  // For AVAudioFrameCount, AVAudioFramePosition
import Accelerate    // For vDSP bulk copy

/// Thread-safe streaming audio buffer optimized for real-time audio
///
/// Design principles:
/// - os_unfair_lock for real-time safety
/// - Lock held only for index/pointer bookkeeping, not sample copying
/// - Ring buffer for O(1) chunk dequeue
/// - Virtual silence chunks to avoid memory allocation
public final class StreamingAudioBuffer: @unchecked Sendable {
    // ...
}
```

### 1.2 Ring Buffer Design

Replace `[AudioChunk]` array with ring buffer to avoid O(n) `removeFirst()`:

```swift
// Ring buffer with fixed capacity matching maxSegments from spec
private var chunkRing: [AudioChunk?]
private var ringHead: Int = 0  // Next slot to read
private var ringTail: Int = 0  // Next slot to write
private var ringCount: Int = 0 // Current number of chunks

// Capacity must be >= maxSegments (1000) to handle "many tiny segments" case
// Using 1024 for power-of-2 efficiency in modulo operations
private static let ringCapacity = 1024

// O(1) enqueue
private func ringEnqueue(_ chunk: AudioChunk) -> Bool {
    guard ringCount < Self.ringCapacity else { return false }
    chunkRing[ringTail] = chunk
    ringTail = (ringTail + 1) % Self.ringCapacity
    ringCount += 1
    return true
}

// O(1) dequeue
private func ringDequeue() -> AudioChunk? {
    guard ringCount > 0 else { return nil }
    let chunk = chunkRing[ringHead]
    chunkRing[ringHead] = nil  // Release reference
    ringHead = (ringHead + 1) % Self.ringCapacity
    ringCount -= 1
    return chunk
}

// O(1) peek
private func ringPeek() -> AudioChunk? {
    guard ringCount > 0 else { return nil }
    return chunkRing[ringHead]
}
```

### 1.3 Bulk Copy Operations

Replace per-sample loops with bulk operations (outside lock critical section):

```swift
case .audio(let samples):
    // Bulk copy using memcpy (simpler and correct for 1D contiguous data)
    samples.withUnsafeBufferPointer { srcBuffer in
        let srcPtr = srcBuffer.baseAddress! + Int(frameOffsetInCurrentChunk)
        let dstPtr = output + Int(framesWritten)
        memcpy(dstPtr, srcPtr, framesToCopy * MemoryLayout<Float>.size)
    }

case .silence(let frameCount):
    // Bulk zero using vDSP_vclr (correct for strided fill)
    vDSP_vclr(output + Int(framesWritten), 1, vDSP_Length(framesToCopy))
```

> **Why memcpy for audio?** `vDSP_mmov` is designed for 2D matrix operations with row/column strides. For contiguous 1D float arrays, `memcpy` is simpler, correct, and equally fast.

### 1.4 Lock-Minimal readFrames

Structure `readFrames()` to minimize time under lock:

```swift
func readFrames(
    into output: UnsafeMutablePointer<Float32>,
    count: AVAudioFrameCount
) -> (framesRead: AVAudioFrameCount, isComplete: Bool, hadError: Bool, wasSpeech: Bool) {

    // Phase 1: Under lock - get chunk info and update indices
    let readInfo: ReadInfo = withLock {
        // ... compute what to read, update indices
        // Return info struct with pointers/indices, don't copy samples
    }

    // Phase 2: Outside lock - bulk copy samples
    performBulkCopy(readInfo, into: output)

    // Phase 3: Under lock - dequeue consumed chunks, check completion
    let result: ReadResult = withLock {
        // ... dequeue if needed, return final state
    }

    return result
}
```

> **Real-time safety note:** `os_unfair_lock` can briefly block if contended. For absolute RT safety, consider `os_unfair_lock_trylock()` with silence fallback if lock unavailable. In practice, lock hold times are so short (<1μs) that contention is extremely rare. Monitor in production and add try-lock path if audio glitches observed.

### 1.5 Speech Detection for TTFA

Add `wasSpeech` return value to distinguish audio from silence:

```swift
struct ReadResult {
    let framesRead: AVAudioFrameCount
    let isComplete: Bool
    let hadError: Bool
    let wasSpeech: Bool  // True if any frames came from .audio chunk
}
```

### 1.6 Segment Count Limit

Add protection against pathological SSML. The ring capacity (1024) exceeds maxSegments (1000), so we enforce the limit in `enqueue()`:

```swift
static let maxSegments = 1000

func enqueue(_ chunk: AudioChunk) async -> Bool {
    // Check segment limit BEFORE backpressure polling
    let currentCount = withLock { ringCount }
    if currentCount >= Self.maxSegments {
        print("StreamingAudioBuffer: Segment limit (\(Self.maxSegments)) reached, dropping chunk")
        return true  // Don't stop synthesis, just drop excess
    }

    // Now do normal backpressure check on buffered frames
    // ... rest of enqueue with frame-based backpressure
}
```

**Invariant:** `ringCapacity (1024) > maxSegments (1000)` ensures we never hit ring-full before segment limit.

**Segment limit behavior:**
- When limit reached, excess chunks are dropped (not enqueued)
- Synthesis continues (returns `true`) to avoid breaking the Task loop
- Log warning with rate limiting (once per synthesis, not per dropped chunk)
- This is a DoS protection; normal SSML rarely exceeds 100 segments

```swift
// Rate-limited logging
private var hasLoggedSegmentLimit = false

if currentCount >= Self.maxSegments {
    if !hasLoggedSegmentLimit {
        print("StreamingAudioBuffer: Segment limit (\(Self.maxSegments)) reached, excess dropped")
        hasLoggedSegmentLimit = true
    }
    return true
}
```

### 1.7 Full Implementation

**File:** `Shared/StreamingAudioBuffer.swift` (~200 lines)

Key methods:
- `init()` - Pre-allocate ring buffer
- `enqueue(_:) async -> Bool` - Producer, with backpressure polling
- `readFrames(into:count:) -> ReadResult` - Consumer, lock-minimal
- `markComplete()` - Signal end of synthesis
- `markFailed(error:)` - Signal error
- `reset()` - Cancel/cleanup
- `hasMinimumBuffer: Bool` - Playback threshold
- `bufferedFrames: AVAudioFramePosition` - Diagnostics

---

## Phase 2: Integration with AudioUnit

**Goal:** Modify `KokoroSynthesisAudioUnit.swift` to use `StreamingAudioBuffer`.

### 2.0 NSLock Migration (CRITICAL)

The current `KokoroSynthesisAudioUnit.swift` uses `NSLock` (`bufferLock`) which is NOT real-time safe. This phase explicitly removes/replaces it:

**Current code to remove:**
```swift
// DELETE these from KokoroSynthesisAudioUnit:
private let bufferLock = NSLock()  // NOT RT-safe

// DELETE all usages like:
bufferLock.lock()
// ...
bufferLock.unlock()

// DELETE per-sample loops in render block:
for i in 0..<Int(frameCount) { ... }
```

**Replace with:**
```swift
// NEW: RT-safe lock for state (not buffer contents)
private var stateLock = os_unfair_lock()

// Buffer operations use StreamingAudioBuffer's internal lock
// Render block uses vDSP bulk operations, not per-sample loops
```

**Migration checklist:**
- [ ] Remove `bufferLock: NSLock` property
- [ ] Remove all `bufferLock.lock()`/`unlock()` calls
- [ ] Add `stateLock: os_unfair_lock` for `_activeStreamingBuffer` and `_currentSynthesisTask`
- [ ] Replace per-sample render loops with `vDSP_vclr` for silence
- [ ] Delegate all buffer operations to `StreamingAudioBuffer`

### 2.1 New Properties

Add to `KokoroSynthesisAudioUnit`:

```swift
// State synchronization
private var stateLock = os_unfair_lock()
private var _activeStreamingBuffer: StreamingAudioBuffer?
private var _currentSynthesisTask: Task<Void, Never>?

// Feature flag
private var useStreamingMode = true

// TTFA tracking (DEBUG only)
#if DEBUG
private var hasEmittedFirstSpeech = false
var onFirstSpeechFrame: (() -> Void)?
#endif
```

### 2.2 Thread-Safe Accessors

```swift
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

> **os_unfair_lock in Swift:** The declaration `private var stateLock = os_unfair_lock()` compiles on macOS 10.12+/iOS 10+. The type is `os_unfair_lock_s` but the initializer `os_unfair_lock()` returns the zero-initialized struct. Verify compilation early in Phase 1.

### 2.3 Playback Start Behavior

**`minBufferBeforeStart` counts ALL frames including silence.**

This means:
- If first segment is a `<break time="1s"/>`, playback starts after 250ms of silence is buffered
- User hears silence promptly, then speech when ready
- This is intentional: responsive feel even with leading pauses

**TTFA measurement** uses `wasSpeech` flag to find first *speech* audio, not first output.

### 2.5 Format Validation

Add to `init()`:

```swift
// After output bus setup
validateOutputFormat()

private func validateOutputFormat() {
    guard let format = _outputBusses[0].format else {
        useStreamingMode = false
        print("KokoroSynthesisAudioUnit: No output format, using non-streaming mode")
        return
    }

    let isCompatible = format.sampleRate == Constants.sampleRate &&
                       format.channelCount == 1 &&
                       format.commonFormat == .pcmFormatFloat32

    if !isCompatible {
        useStreamingMode = false
        print("KokoroSynthesisAudioUnit: Format mismatch, using non-streaming mode")
    }
}
```

### 2.6 Modified synthesizeSpeechRequest

Refactor to use streaming:

```swift
public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
    // Cancel existing
    cancelCurrentSynthesis()

    #if DEBUG
    hasEmittedFirstSpeech = false
    #endif

    // Check streaming mode
    guard useStreamingMode else {
        synthesizeSpeechRequestLegacy(request)
        return
    }

    // Parse SSML
    let segments = SSMLParser.parse(request.ssmlRepresentation)
    let voiceId = mapVoiceIdentifier(request.voice)

    // Create buffer
    let buffer = StreamingAudioBuffer()
    activeStreamingBuffer = buffer

    // Start synthesis task
    let task = Task { [weak self] in
        await self?.synthesizeSegments(segments, voiceId: voiceId, into: buffer)
    }
    currentSynthesisTask = task
}

private func synthesizeSegments(
    _ segments: [SSMLParser.SynthesisSegment],
    voiceId: String,
    into buffer: StreamingAudioBuffer
) async {
    do {
        for segment in segments {
            try Task.checkCancellation()

            // Handle pause
            if segment.pauseBefore > 0 {
                let clamped = min(segment.pauseBefore, StreamingAudioBuffer.maxPauseDuration)
                let frames = Int(clamped * Float(Constants.sampleRate))
                guard frames > 0 else { continue }

                let shouldContinue = await buffer.enqueue(.silence(frameCount: frames))
                if !shouldContinue { return }
            }

            // Skip empty
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            try Task.checkCancellation()

            // Generate audio
            let audio = try await KokoroEngine.shared.generateAudio(
                text: text,
                voiceId: voiceId,
                speed: segment.rate
            )

            // Validate samples
            let validated = audio.map { $0.isNaN || $0.isInfinite ? 0.0 : $0 }

            let shouldContinue = await buffer.enqueue(.audio(validated))
            if !shouldContinue { return }
        }

        buffer.markComplete()

    } catch is CancellationError {
        // Clean exit
    } catch {
        print("KokoroSynthesisAudioUnit: Synthesis error: \(error)")
        buffer.markFailed(error: error)
    }
}
```

### 2.7 Modified Render Block

```swift
public override var internalRenderBlock: AUInternalRenderBlock {
    return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputAudioBufferList, _, _ in
        guard let self = self else { return kAudio_ParamError }

        let outputPtr = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        guard outputPtr.count > 0,
              let output = outputPtr[0].mData?.assumingMemoryBound(to: Float32.self) else {
            return kAudio_ParamError
        }

        // Get buffer (thread-safe)
        guard let buffer = self.activeStreamingBuffer else {
            vDSP_vclr(output, 1, vDSP_Length(frameCount))
            return noErr
        }

        // Wait for minimum buffer
        guard buffer.hasMinimumBuffer else {
            vDSP_vclr(output, 1, vDSP_Length(frameCount))
            return noErr
        }

        // Read frames
        let result = buffer.readFrames(into: output, count: frameCount)

        // Fill remainder with silence
        if result.framesRead < frameCount {
            let remaining = frameCount - result.framesRead
            vDSP_vclr(output + Int(result.framesRead), 1, vDSP_Length(remaining))
        }

        // TTFA tracking (RT-safe: set atomic flag, notify off render thread)
        #if DEBUG
        if result.wasSpeech && !self.hasEmittedFirstSpeech {
            self.hasEmittedFirstSpeech = true
            // Don't call closure on RT thread - dispatch async to main
            if let callback = self.onFirstSpeechFrame {
                DispatchQueue.main.async { callback() }
            }
        }
        #endif

        // Completion
        if result.isComplete {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            if result.hadError {
                print("KokoroSynthesisAudioUnit: Completed with error")
            }
            self.activeStreamingBuffer = nil
        }

        return noErr
    }
}
```

### 2.8 Cancellation

```swift
private func cancelCurrentSynthesis() {
    let (task, buffer) = withStateLock {
        let t = _currentSynthesisTask
        let b = _activeStreamingBuffer
        _currentSynthesisTask = nil
        _activeStreamingBuffer = nil
        return (t, b)
    }

    task?.cancel()
    buffer?.reset()
}

public override func cancelSpeechRequest() {
    print("KokoroSynthesisAudioUnit: Cancelling")
    cancelCurrentSynthesis()
    pendingRequests.removeAll()
}
```

### 2.9 Legacy Fallback

Rename existing implementation:

```swift
private func synthesizeSpeechRequestLegacy(_ request: AVSpeechSynthesisProviderRequest) {
    // ... existing non-streaming implementation unchanged
}
```

---

## Phase 3: Documentation

**Goal:** Update user-facing docs per spec "User Guidance" section.

### 3.1 README Update

Add to `README.md` or create `docs/SSML-BEST-PRACTICES.md`:

```markdown
## SSML Best Practices for Optimal Latency

For the best experience with long texts:

- Use `<s>` tags around sentences
- Use `<p>` tags around paragraphs
- Avoid single segments longer than ~50 words

This allows audio to start playing within 500ms regardless of total text length.
```

---

## Phase 4: Testing

### 4.1 Unit Tests

**File:** `Tests/StreamingAudioBufferTests.swift` (~150 lines)

```swift
import XCTest
@testable import KokoroVoiceShared

final class StreamingAudioBufferTests: XCTestCase {

    // MARK: - Basic Flow

    func testEnqueueDequeue() async {
        let buffer = StreamingAudioBuffer()
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]

        _ = await buffer.enqueue(.audio(samples))
        buffer.markComplete()

        var output = [Float](repeating: 0, count: 4)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 4)
        }

        XCTAssertEqual(result.framesRead, 4)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.wasSpeech)
        XCTAssertEqual(output, samples)
    }

    func testVirtualSilence() async {
        let buffer = StreamingAudioBuffer()

        _ = await buffer.enqueue(.silence(frameCount: 100))
        buffer.markComplete()

        var output = [Float](repeating: 1.0, count: 100)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 100)
        }

        XCTAssertEqual(result.framesRead, 100)
        XCTAssertFalse(result.wasSpeech)
        XCTAssertTrue(output.allSatisfy { $0 == 0.0 })
    }

    // MARK: - Backpressure

    func testBackpressure() async {
        let buffer = StreamingAudioBuffer()

        // Fill to max
        let bigChunk = [Float](repeating: 0, count: Int(StreamingAudioBuffer.maxBufferedFrames))
        _ = await buffer.enqueue(.audio(bigChunk))

        // Next enqueue should poll-wait
        let expectation = XCTestExpectation(description: "Enqueue completes after drain")

        Task {
            _ = await buffer.enqueue(.audio([1.0]))
            expectation.fulfill()
        }

        // Drain some
        var output = [Float](repeating: 0, count: 10000)
        output.withUnsafeMutableBufferPointer { ptr in
            _ = buffer.readFrames(into: ptr.baseAddress!, count: 10000)
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Reset

    func testResetStopsEnqueue() async {
        let buffer = StreamingAudioBuffer()

        // Start enqueue that will block
        let bigChunk = [Float](repeating: 0, count: Int(StreamingAudioBuffer.maxBufferedFrames))
        _ = await buffer.enqueue(.audio(bigChunk))

        let enqueueTask = Task {
            await buffer.enqueue(.audio([1.0]))
        }

        // Reset should cause enqueue to return false
        buffer.reset()

        let continued = await enqueueTask.value
        XCTAssertFalse(continued)
    }

    // MARK: - Many Tiny Segments (ring capacity test)

    func testManyTinySegments() async {
        let buffer = StreamingAudioBuffer()

        // Enqueue 500 tiny audio chunks (well under maxSegments=1000)
        for i in 0..<500 {
            let tiny = [Float](repeating: Float(i), count: 10)
            let cont = await buffer.enqueue(.audio(tiny))
            XCTAssertTrue(cont, "Should accept chunk \(i)")
        }

        buffer.markComplete()

        // Verify all can be read
        var output = [Float](repeating: 0, count: 5000)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 5000)
        }
        XCTAssertEqual(result.framesRead, 5000)
        XCTAssertTrue(result.isComplete)
    }

    func testSegmentLimitEnforced() async {
        let buffer = StreamingAudioBuffer()

        // Enqueue exactly maxSegments
        for _ in 0..<StreamingAudioBuffer.maxSegments {
            _ = await buffer.enqueue(.audio([1.0]))
        }

        // Next should be dropped (returns true but doesn't enqueue)
        let cont = await buffer.enqueue(.audio([2.0]))
        XCTAssertTrue(cont, "Should return true (don't stop synthesis)")

        // Verify by reading: should get exactly maxSegments frames
        buffer.markComplete()
        var output = [Float](repeating: 0, count: StreamingAudioBuffer.maxSegments + 10)
        output.withUnsafeMutableBufferPointer { ptr in
            let result = buffer.readFrames(into: ptr.baseAddress!, count: UInt32(ptr.count))
            XCTAssertEqual(Int(result.framesRead), StreamingAudioBuffer.maxSegments)
        }
    }

    // MARK: - TTFA Accuracy

    func testWasSpeechWithMixedChunks() async {
        let buffer = StreamingAudioBuffer()

        // Silence then audio
        _ = await buffer.enqueue(.silence(frameCount: 100))
        _ = await buffer.enqueue(.audio([1.0, 2.0, 3.0]))
        buffer.markComplete()

        // First read: silence only
        var out1 = [Float](repeating: 0, count: 50)
        let r1 = out1.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 50)
        }
        XCTAssertFalse(r1.wasSpeech, "First read is silence")

        // Second read: remaining silence + start of audio
        var out2 = [Float](repeating: 0, count: 53)
        let r2 = out2.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 53)
        }
        XCTAssertTrue(r2.wasSpeech, "Second read includes speech")
    }

    // MARK: - Thread Safety (run with TSan)

    func testConcurrentAccess() async {
        let buffer = StreamingAudioBuffer()

        // Producer
        let producer = Task {
            for i in 0..<100 {
                let samples = [Float](repeating: Float(i), count: 100)
                let cont = await buffer.enqueue(.audio(samples))
                if !cont { break }
            }
            buffer.markComplete()
        }

        // Consumer
        let consumer = Task {
            var output = [Float](repeating: 0, count: 50)
            var totalRead = 0
            while true {
                let result = output.withUnsafeMutableBufferPointer { ptr in
                    buffer.readFrames(into: ptr.baseAddress!, count: 50)
                }
                totalRead += Int(result.framesRead)
                if result.isComplete { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        await producer.value
        await consumer.value
    }
}
```

### 4.2 Integration Tests

**File:** `Tests/StreamingIntegrationTests.swift` (~100 lines)

> **Note on TTFA testing:** Measuring wall-clock TTFA < 500ms in CI is inherently flaky. Instead, test invariants that imply good TTFA (e.g., first chunk enqueued before synthesis completes).

```swift
import XCTest
@testable import KokoroVoiceShared

final class StreamingIntegrationTests: XCTestCase {

    func testShortTextProducesNonZeroAudio() async throws {
        // Verify streaming mode produces actual audio samples
        // Don't compare exact waveforms (KokoroEngine may have non-determinism)
    }

    func testFirstChunkEnqueuedBeforeSynthesisCompletes() async throws {
        // For long text, verify first chunk is available while synthesis ongoing
        // This validates streaming behavior without wall-clock timing
    }

    func testCancellationStopsEnqueuing() async throws {
        // Start long synthesis, cancel, verify no more chunks enqueued
        // Buffer should have isReset = true
    }

    func testRapidRequestSwitching() async throws {
        // Rapid fire multiple requests, verify no crashes, no leaks
        // Previous task cancelled, new buffer active
    }

    func testCompletionSignaledAfterAllChunksConsumed() async throws {
        // Verify isComplete only when synthesis done AND buffer empty
    }
}
```

**TTFA Measurement (Manual/DEBUG only):**

For actual TTFA measurement, use the DEBUG hook with manual testing:

```swift
#if DEBUG
// In test or debug session:
let startTime = CFAbsoluteTimeGetCurrent()
audioUnit.onFirstSpeechFrame = {
    let ttfa = CFAbsoluteTimeGetCurrent() - startTime
    print("TTFA: \(ttfa * 1000)ms")
}
#endif
```

### 4.3 Thread Sanitizer

**For Xcode-based testing (recommended):**
```
Product → Test (Cmd+U) with Thread Sanitizer enabled in scheme diagnostics
```

**For SwiftPM tests (shared components only):**
```bash
swift test --sanitize=thread
```

> **Note:** The `KokoroVoiceExtension` target is an App Extension and cannot be tested directly via SwiftPM. Use Xcode's test runner for integration tests. Unit tests for `StreamingAudioBuffer` in the `KokoroVoiceShared` framework can use either runner.

---

## Verification Checklist

Before marking complete:

**StreamingAudioBuffer:**
- [ ] Ring buffer with capacity >= 1024 (O(1) dequeue)
- [ ] Sample copying uses vDSP (outside lock)
- [ ] Lock critical sections < 1μs (no loops, no allocations inside lock)
- [ ] `wasSpeech` flag correctly tracks audio vs silence
- [ ] Backpressure polling works (10ms sleep, no lock held across await)
- [ ] Reset flag stops all operations gracefully
- [ ] Segment count capped at 1000 (ring capacity 1024 > maxSegments 1000)
- [ ] Pause duration clamped to 30s
- [ ] Imports: `Foundation`, `os`, `AVFoundation`, `Accelerate`

**AudioUnit Integration:**
- [ ] NSLock (`bufferLock`) completely removed
- [ ] `stateLock: os_unfair_lock` protects shared pointers only
- [ ] Render block uses vDSP for silence (no per-sample loops)
- [ ] `minBufferBeforeStart` counts silence frames (documented behavior)
- [ ] Format validation with non-streaming fallback
- [ ] TTFA hook fires on first speech frame (DEBUG only)
- [ ] NaN/Inf samples sanitized before enqueue

**Documentation:**
- [ ] User guidance for SSML structure added to README or docs/

**Testing:**
- [ ] Unit tests pass (including many-tiny-segments test)
- [ ] Integration tests validate invariants (not wall-clock timing)
- [ ] Thread Sanitizer clean
- [ ] Manual test: VoiceOver with long passage
- [ ] Manual TTFA measurement < 500ms for multi-segment text

**Framework Dependencies:**
- [ ] `Accelerate.framework` linked to KokoroVoiceShared target
- [ ] `os_unfair_lock()` declaration compiles (verify early in Phase 1)

---

## File Summary

| File | Action | Lines |
|------|--------|-------|
| `Shared/StreamingAudioBuffer.swift` | Create | ~200 |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Modify | ~150 |
| `Tests/StreamingAudioBufferTests.swift` | Create | ~200 |
| `Tests/StreamingIntegrationTests.swift` | Create | ~100 |
| `README.md` or `docs/SSML-BEST-PRACTICES.md` | Update/Create | ~20 |

**Total:** ~670 lines
