# Review: Spec 0002 - Chunked Audio Streaming

## Implementation Summary

Implemented chunked audio streaming for low-latency TTS playback in KokoroSynthesisAudioUnit.

### Files Changed

| File | Action | Lines |
|------|--------|-------|
| `Shared/StreamingAudioBuffer.swift` | Created | ~290 |
| `KokoroVoiceExtension/KokoroSynthesisAudioUnit.swift` | Modified | ~700 (rewrite) |
| `KokoroVoiceExtension/SSMLParser.swift` | Modified | 1 (Sendable) |
| `Tests/StreamingAudioBufferTests/StreamingAudioBufferTests.swift` | Created | ~400 |
| `README.md` | Modified | +22 (SSML docs) |
| `Package.swift` | Modified | +5 (test target) |

### Spec Compliance Checklist

#### Goals

- [x] **First audio in <500ms** - Implemented via `minBufferBeforeStart` (250ms threshold)
- [x] **Progressive streaming** - Synthesis task enqueues chunks while render consumes
- [x] **Seamless playback** - Ring buffer with bulk copy operations
- [x] **Graceful degradation** - Buffer underrun produces silence (vDSP_vclr)

#### Key Design Decisions

1. **StreamingAudioBuffer**
   - [x] Ring buffer with capacity 1024 (O(1) enqueue/dequeue)
   - [x] `os_unfair_lock` for real-time safety
   - [x] Lock held only for bookkeeping, bulk copy outside lock
   - [x] Virtual silence chunks (no memory allocation for pauses)
   - [x] Segment limit of 1000 (DoS protection)
   - [x] Backpressure via polling (never holds lock across await)

2. **Audio Unit Integration**
   - [x] Replaced NSLock with os_unfair_lock (RT-safe)
   - [x] Uses vDSP_vclr for silence (not per-sample loops)
   - [x] Legacy fallback mode for format mismatches
   - [x] TTFA tracking hook (DEBUG only)

3. **Thread Safety**
   - [x] `stateLock` protects shared pointers
   - [x] Buffer has internal lock for chunk operations
   - [x] All closures marked `@Sendable`
   - [x] `SynthesisSegment` made `Sendable`

#### Traps Avoided

- [x] No NSLock on render thread
- [x] Render thread never blocks (underrun → silence)
- [x] Lock never held across await
- [x] No async/await in render block
- [x] All shared state access uses lock
- [x] Task reference stored and cancelled explicitly
- [x] Consumed chunks dequeued (no memory growth)
- [x] Format validated with fallback
- [x] NaN/Inf samples sanitized
- [x] Silence chunks are virtual (no allocation)
- [x] Pause duration clamped to 30s

### Test Coverage

| Area | Tests |
|------|-------|
| Basic enqueue/dequeue | ✓ |
| Virtual silence | ✓ |
| Partial reads | ✓ |
| Multiple chunks | ✓ |
| Mixed audio/silence | ✓ |
| Minimum buffer threshold | ✓ |
| Reset/cancellation | ✓ |
| Error handling | ✓ |
| wasSpeech detection | ✓ |
| Many tiny segments | ✓ |
| Segment limit | ✓ |
| Concurrent access | ✓ |
| Constants validation | ✓ |

### Known Limitations

1. **No sub-sentence chunking** - SSML segment boundaries are chunk points (per spec non-goal)
2. **TTFA for single long segment** - Will exceed 500ms for very long first segments (documented in spec)
3. **Integration tests require model** - Full E2E testing needs Xcode with model files

### Documentation

- [x] SSML best practices added to README
- [x] Code comments explain RT-safety constraints
- [x] Spec traps documented in implementation

## Post-Review Fixes

The 3-way review (Gemini, Codex, Claude) identified two race conditions that were addressed:

### 1. Legacy Variables Race Condition (be1f3ad)

**Issue:** After replacing NSLock with os_unfair_lock, the legacy variables (`legacyBuffer`, `legacyFramePosition`, `legacySynthesisCompletedEmpty`) were left unprotected and accessed concurrently from render thread and synthesis queue.

**Fix:**
- Renamed to backing storage with `_` prefix
- Added thread-safe accessors using `withStateLock`
- Batched lock acquisitions in `renderLegacy()` for RT-safety
- Updated `cancelCurrentSynthesis()` to clear legacy state atomically

### 2. pendingRequests Race Condition (32374dd)

**Issue:** `pendingRequests` array was accessed concurrently from async Task (`processPendingRequests`) and system callbacks (`synthesizeSpeechRequest`, `cancelSpeechRequest`), risking request loss or corruption.

**Fix:**
- Renamed to `_pendingRequests` (backing storage)
- Added thread-safe operations: `appendPendingRequest()`, `takePendingRequests()`, `clearPendingRequests()`
- `takePendingRequests()` atomically consumes and clears the queue, preventing request loss during concurrent access

## Lessons Learned

1. **Swift 6 Concurrency** - Required `@Sendable` annotations and protocol conformance for closures crossing isolation boundaries
2. **os_unfair_lock in Swift** - Works with `os_unfair_lock()` initializer; must pass as `&lock`
3. **Ring Buffer vs Array** - Critical for O(1) dequeue; Swift Array.removeFirst() is O(n)
4. **Bulk Operations** - `memcpy` simpler than vDSP for 1D contiguous arrays; vDSP_vclr for zeroing
5. **Complete Synchronization Audit** - When replacing a locking mechanism, audit ALL shared state, not just the primary target

## Verification

```bash
# Build
swift build  # ✓ Clean

# Unit Tests
swift test --filter StreamingAudioBufferTests  # ✓ All 21 tests pass

# All Tests
swift test  # ✓ All tests pass
```

## PR Ready

Implementation complete and tested. Ready for architect review.
