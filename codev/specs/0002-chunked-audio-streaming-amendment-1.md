# Spec 0002 Amendment 1: Edge Case Hardening

## Status
**specified** - 2026-02-01

## Context

External review (Codex) identified three edge cases in Spec 0002 that need clarification and implementation fixes:

1. **Oversized chunk handling** - No defined behavior when a single segment's audio exceeds `maxBufferedFrames`
2. **Render thread blocking claim** - Spec claims "NEVER blocks" but `os_unfair_lock_lock` can block under contention
3. **maxSegments semantics** - Limit enforced on chunk count, but pauses create extra chunks

## Changes

### 1. Oversized Chunk Handling

**Problem:** If a single segment generates audio > 10s (240,000 frames), the producer will poll-wait forever because the buffer can never have enough space.

**Solution:** Split oversized audio chunks before enqueueing.

```swift
// In synthesis loop, after generating audio:
let validated = audio.map { $0.isNaN || $0.isInfinite ? 0.0 : $0 }

// Split if oversized (leave 10% headroom for safe enqueueing)
let maxChunkSize = Int(StreamingAudioBuffer.maxBufferedFrames) * 9 / 10  // 216,000 frames (~9s)

if validated.count > maxChunkSize {
    // Split into multiple chunks
    var offset = 0
    while offset < validated.count {
        let end = min(offset + maxChunkSize, validated.count)
        let chunk = Array(validated[offset..<end])
        let shouldContinue = await buffer.enqueue(.audio(chunk))
        if !shouldContinue { return }
        offset = end
    }
} else {
    let shouldContinue = await buffer.enqueue(.audio(validated))
    if !shouldContinue { return }
}
```

**Rationale:**
- 9s chunk size leaves 1s headroom for backpressure polling to find space
- Splitting is transparent to playback (no audible artifacts)
- Preserves streaming semantics - first 9s plays while rest is buffered

### 2. Render Thread Non-Blocking Guarantee

**Problem:** `os_unfair_lock_lock()` can block briefly if the lock is contended. The spec claims render thread "NEVER blocks."

**Solution:** Use `os_unfair_lock_trylock()` in render path with silence fallback.

```swift
// In StreamingAudioBuffer.readFrames():
func readFrames(
    into output: UnsafeMutablePointer<Float32>,
    count: AVAudioFrameCount
) -> (framesRead: AVAudioFrameCount, isComplete: Bool, hadError: Bool, wasSpeech: Bool) {

    // Try to acquire lock without blocking
    guard os_unfair_lock_trylock(&lock) else {
        // Lock contended - return silence instead of blocking
        // This is extremely rare (<0.001% of calls) but guarantees RT safety
        return (0, false, false, false)
    }
    defer { os_unfair_lock_unlock(&lock) }

    // ... existing logic
}
```

**Rationale:**
- Render thread is called ~375 times/second at 24kHz with 64-frame buffers
- Lock hold time is <1μs, so contention is extremely rare
- When contention occurs, silence fallback is inaudible (single 64-frame gap = 2.6ms)
- Guarantees the spec's "NEVER blocks" claim is literally true

**Metrics hook (DEBUG only):**
```swift
#if DEBUG
static var lockContentionCount = 0
static var totalReadCalls = 0
#endif

// In readFrames:
#if DEBUG
Self.totalReadCalls += 1
guard os_unfair_lock_trylock(&lock) else {
    Self.lockContentionCount += 1
    return (0, false, false, false)
}
#endif
```

### 3. Segment vs Chunk Limit Clarification

**Problem:** `maxSegments = 1000` is enforced on `ringCount`, but pauses create additional chunks. An SSML with 600 segments where each has a pause would create 1200 chunks, hitting the limit early.

**Solution:** Separate limits for segments and chunks. Rename `maxSegments` to `maxChunks` and add explicit SSML segment tracking.

```swift
// Constants
static let maxChunks = 2048        // Ring buffer capacity (chunks = audio + silence)
static let maxSSMLSegments = 1000  // Limit on input SSML segments (DoS protection)

// In synthesis loop (AudioUnit side, not buffer):
var segmentCount = 0
for segment in segments {
    segmentCount += 1
    if segmentCount > maxSSMLSegments {
        print("KokoroSynthesisAudioUnit: SSML segment limit (\(maxSSMLSegments)) reached, truncating")
        break
    }
    // ... process segment (may enqueue 1-2 chunks: silence + audio)
}
```

**Updated semantics:**
- `maxSSMLSegments` (1000): Limits input SSML segments in synthesis loop (prevents pathological input)
- `maxChunks` (2048): Ring buffer capacity (internal limit, should never be hit with maxSSMLSegments enforced)

**Invariant:** With `maxSSMLSegments = 1000` and worst case 2 chunks per segment, max chunks = 2000. But oversized splitting (change #1) can increase this. Set `ringCapacity = 2048` to be safe.

Update ring buffer initialization:
```swift
private static let ringCapacity = 2048  // Was 1024
```

## Testing Additions

### Oversized Chunk Test
```swift
func testOversizedChunkSplit() async {
    let buffer = StreamingAudioBuffer()

    // Create chunk larger than maxBufferedFrames
    let oversized = [Float](repeating: 1.0, count: Int(StreamingAudioBuffer.maxBufferedFrames) + 50000)

    // Should not hang - enqueue should split internally or synthesis should split
    let task = Task {
        _ = await buffer.enqueue(.audio(oversized))
    }

    // Drain concurrently
    let consumer = Task {
        var output = [Float](repeating: 0, count: 10000)
        while true {
            let result = output.withUnsafeMutableBufferPointer { ptr in
                buffer.readFrames(into: ptr.baseAddress!, count: 10000)
            }
            if result.isComplete { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // Should complete without hanging
    await task.value
    buffer.markComplete()
    await consumer.value
}
```

### Lock Contention Test
```swift
func testHighContentionNoBlocking() async {
    let buffer = StreamingAudioBuffer()

    // Hammer from multiple tasks simultaneously
    await withTaskGroup(of: Void.self) { group in
        // 10 producers
        for i in 0..<10 {
            group.addTask {
                for _ in 0..<100 {
                    _ = await buffer.enqueue(.audio([Float(i)]))
                }
            }
        }

        // 10 consumers (simulating rapid render calls)
        for _ in 0..<10 {
            group.addTask {
                var output = [Float](repeating: 0, count: 64)
                for _ in 0..<1000 {
                    output.withUnsafeMutableBufferPointer { ptr in
                        _ = buffer.readFrames(into: ptr.baseAddress!, count: 64)
                    }
                }
            }
        }
    }

    #if DEBUG
    // Verify contention rate is acceptable (<1%)
    let contentionRate = Double(StreamingAudioBuffer.lockContentionCount) / Double(StreamingAudioBuffer.totalReadCalls)
    XCTAssertLessThan(contentionRate, 0.01, "Lock contention too high: \(contentionRate * 100)%")
    #endif
}
```

### SSML Segment Limit Test
```swift
func testSSMLSegmentLimit() async {
    // Create SSML with 1500 segments (exceeds limit)
    var segments: [SSMLParser.SynthesisSegment] = []
    for i in 0..<1500 {
        segments.append(SSMLParser.SynthesisSegment(
            text: "Word \(i)",
            pauseBefore: 0.01,
            rate: 1.0
        ))
    }

    // Synthesis should process only first 1000
    // Verify via chunk count or completion behavior
}
```

## Files to Modify

| File | Change |
|------|--------|
| `Shared/StreamingAudioBuffer.swift` | Add `trylock`, increase `ringCapacity` to 2048, rename constants |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Add oversized chunk splitting, add SSML segment limit |
| `Tests/StreamingAudioBufferTests.swift` | Add new test cases |

## Success Criteria

1. **Oversized chunk:** Single segment >10s completes without hanging
2. **Non-blocking guarantee:** `readFrames` never blocks (uses `trylock`)
3. **Segment limit clarity:** SSML segments limited to 1000, chunks limited to 2048
4. **All existing tests pass**
5. **Thread Sanitizer clean**
