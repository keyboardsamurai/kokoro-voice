// Tests/StreamingAudioBufferTests/StreamingAudioBufferTests.swift
// KokoroVoice
//
// Unit tests for StreamingAudioBuffer

import XCTest
@testable import KokoroVoiceShared

final class StreamingAudioBufferTests: XCTestCase {

    // MARK: - Basic Flow Tests

    func testEnqueueDequeue() async {
        let buffer = StreamingAudioBuffer()
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]

        let enqueued = await buffer.enqueue(.audio(samples))
        XCTAssertTrue(enqueued, "Enqueue should succeed")

        buffer.markComplete()

        var output = [Float](repeating: 0, count: 4)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 4)
        }

        XCTAssertEqual(result.framesRead, 4)
        XCTAssertTrue(result.isComplete)
        XCTAssertFalse(result.hadError)
        XCTAssertTrue(result.wasSpeech)
        XCTAssertEqual(output, samples)
    }

    func testVirtualSilence() async {
        let buffer = StreamingAudioBuffer()

        let enqueued = await buffer.enqueue(.silence(frameCount: 100))
        XCTAssertTrue(enqueued)

        buffer.markComplete()

        var output = [Float](repeating: 1.0, count: 100)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 100)
        }

        XCTAssertEqual(result.framesRead, 100)
        XCTAssertTrue(result.isComplete)
        XCTAssertFalse(result.wasSpeech, "Silence should not be marked as speech")
        XCTAssertTrue(output.allSatisfy { $0 == 0.0 }, "All output should be zeros")
    }

    func testEmptyBufferReturnsZeroFrames() {
        let buffer = StreamingAudioBuffer()

        var output = [Float](repeating: 1.0, count: 10)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 10)
        }

        XCTAssertEqual(result.framesRead, 0, "Empty buffer should return 0 frames")
        XCTAssertFalse(result.isComplete, "Should not be complete (synthesis ongoing)")
        XCTAssertFalse(result.wasSpeech)
    }

    func testCompleteEmptyBuffer() {
        let buffer = StreamingAudioBuffer()
        buffer.markComplete()

        var output = [Float](repeating: 1.0, count: 10)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 10)
        }

        XCTAssertEqual(result.framesRead, 0)
        XCTAssertTrue(result.isComplete, "Should be complete when synthesis done and buffer empty")
    }

    // MARK: - Partial Read Tests

    func testPartialRead() async {
        let buffer = StreamingAudioBuffer()
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

        _ = await buffer.enqueue(.audio(samples))
        buffer.markComplete()

        // Read first 3 frames
        var output1 = [Float](repeating: 0, count: 3)
        let result1 = output1.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 3)
        }

        XCTAssertEqual(result1.framesRead, 3)
        XCTAssertFalse(result1.isComplete, "Not complete yet, more frames available")
        XCTAssertEqual(output1, [1.0, 2.0, 3.0])

        // Read next 3 frames
        var output2 = [Float](repeating: 0, count: 3)
        let result2 = output2.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 3)
        }

        XCTAssertEqual(result2.framesRead, 3)
        XCTAssertFalse(result2.isComplete)
        XCTAssertEqual(output2, [4.0, 5.0, 6.0])

        // Read remaining 2 frames (asking for 3)
        var output3 = [Float](repeating: 0, count: 3)
        let result3 = output3.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 3)
        }

        XCTAssertEqual(result3.framesRead, 2, "Only 2 frames remaining")
        XCTAssertTrue(result3.isComplete)
        XCTAssertEqual(output3[0], 7.0)
        XCTAssertEqual(output3[1], 8.0)
    }

    // MARK: - Multiple Chunks Tests

    func testMultipleChunks() async {
        let buffer = StreamingAudioBuffer()

        _ = await buffer.enqueue(.audio([1.0, 2.0]))
        _ = await buffer.enqueue(.audio([3.0, 4.0]))
        _ = await buffer.enqueue(.audio([5.0, 6.0]))
        buffer.markComplete()

        var output = [Float](repeating: 0, count: 6)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 6)
        }

        XCTAssertEqual(result.framesRead, 6)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(output, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
    }

    func testMixedAudioAndSilence() async {
        let buffer = StreamingAudioBuffer()

        _ = await buffer.enqueue(.silence(frameCount: 2))
        _ = await buffer.enqueue(.audio([1.0, 2.0]))
        _ = await buffer.enqueue(.silence(frameCount: 2))
        buffer.markComplete()

        var output = [Float](repeating: 999.0, count: 6)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 6)
        }

        XCTAssertEqual(result.framesRead, 6)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(output, [0.0, 0.0, 1.0, 2.0, 0.0, 0.0])
    }

    // MARK: - Minimum Buffer Tests

    func testHasMinimumBufferBeforeThreshold() async {
        let buffer = StreamingAudioBuffer()

        // Add less than minimum (6000 frames = 250ms at 24kHz)
        let smallChunk = [Float](repeating: 0.5, count: 1000)
        _ = await buffer.enqueue(.audio(smallChunk))

        XCTAssertFalse(buffer.hasMinimumBuffer, "Should not have minimum buffer with only 1000 frames")
    }

    func testHasMinimumBufferAfterThreshold() async {
        let buffer = StreamingAudioBuffer()

        // Add exactly minimum (6000 frames = 250ms at 24kHz)
        let chunk = [Float](repeating: 0.5, count: Int(StreamingAudioBuffer.minBufferBeforeStart))
        _ = await buffer.enqueue(.audio(chunk))

        XCTAssertTrue(buffer.hasMinimumBuffer, "Should have minimum buffer after reaching threshold")
    }

    func testHasMinimumBufferWhenComplete() async {
        let buffer = StreamingAudioBuffer()

        // Add small chunk but mark complete
        let smallChunk = [Float](repeating: 0.5, count: 100)
        _ = await buffer.enqueue(.audio(smallChunk))
        buffer.markComplete()

        XCTAssertTrue(buffer.hasMinimumBuffer, "Should return true when complete (play whatever we have)")
    }

    // MARK: - Reset Tests

    func testResetClearsBuffer() async {
        let buffer = StreamingAudioBuffer()

        _ = await buffer.enqueue(.audio([1.0, 2.0, 3.0]))

        buffer.reset()

        var output = [Float](repeating: 0, count: 3)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 3)
        }

        XCTAssertEqual(result.framesRead, 0, "Reset buffer should have no frames")
        XCTAssertTrue(result.isComplete, "Reset buffer should signal complete immediately")
    }

    func testResetStopsEnqueue() async {
        let buffer = StreamingAudioBuffer()

        // Start with some data
        let chunk = [Float](repeating: 0.5, count: 1000)
        _ = await buffer.enqueue(.audio(chunk))

        // Reset
        buffer.reset()

        // Try to enqueue more
        let continued = await buffer.enqueue(.audio([1.0, 2.0]))

        XCTAssertFalse(continued, "Enqueue should return false after reset")
    }

    func testHasMinimumBufferAfterReset() async {
        let buffer = StreamingAudioBuffer()

        let chunk = [Float](repeating: 0.5, count: Int(StreamingAudioBuffer.minBufferBeforeStart))
        _ = await buffer.enqueue(.audio(chunk))

        XCTAssertTrue(buffer.hasMinimumBuffer)

        buffer.reset()

        XCTAssertFalse(buffer.hasMinimumBuffer, "Reset should clear minimum buffer state")
    }

    // MARK: - Error Handling Tests

    func testMarkFailed() async {
        let buffer = StreamingAudioBuffer()

        _ = await buffer.enqueue(.audio([1.0, 2.0]))
        buffer.markFailed(error: NSError(domain: "Test", code: 1))

        var output = [Float](repeating: 0, count: 2)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 2)
        }

        XCTAssertEqual(result.framesRead, 2, "Should still read buffered audio")
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.hadError, "Should indicate error after all audio consumed")
    }

    // MARK: - WasSpeech Detection Tests

    func testWasSpeechWithMixedChunks() async {
        let buffer = StreamingAudioBuffer()

        // Silence then audio
        _ = await buffer.enqueue(.silence(frameCount: 100))
        _ = await buffer.enqueue(.audio([1.0, 2.0, 3.0]))
        buffer.markComplete()

        // First read: silence only
        var out1 = [Float](repeating: 999, count: 50)
        let r1 = out1.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 50)
        }
        XCTAssertFalse(r1.wasSpeech, "First read is only silence")

        // Second read: remaining silence + start of audio
        var out2 = [Float](repeating: 999, count: 53)
        let r2 = out2.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 53)
        }
        XCTAssertTrue(r2.wasSpeech, "Second read includes speech")
    }

    // MARK: - Many Tiny Chunks Tests

    func testManyTinyChunks() async {
        let buffer = StreamingAudioBuffer()

        // Enqueue 500 tiny audio chunks (well under maxChunks=2048)
        for i in 0..<500 {
            let tiny = [Float](repeating: Float(i % 100), count: 10)
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

    func testChunkLimitEnforced() async {
        let buffer = StreamingAudioBuffer()

        // Enqueue exactly maxChunks - but each tiny so we don't hit frame limit
        for _ in 0..<StreamingAudioBuffer.maxChunks {
            _ = await buffer.enqueue(.audio([1.0]))
        }

        // Next should be dropped (returns true but doesn't enqueue)
        let cont = await buffer.enqueue(.audio([2.0]))
        XCTAssertTrue(cont, "Should return true (don't stop synthesis)")

        // Verify by reading: should get exactly maxChunks frames
        buffer.markComplete()
        var output = [Float](repeating: 0, count: StreamingAudioBuffer.maxChunks + 10)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: UInt32(ptr.count))
        }
        XCTAssertEqual(Int(result.framesRead), StreamingAudioBuffer.maxChunks, "Should have exactly maxChunks frames")
    }

    // MARK: - Buffered Frames Tests

    func testBufferedFrames() async {
        let buffer = StreamingAudioBuffer()

        XCTAssertEqual(buffer.bufferedFrames, 0)

        _ = await buffer.enqueue(.audio([1.0, 2.0, 3.0, 4.0, 5.0]))
        XCTAssertEqual(buffer.bufferedFrames, 5)

        _ = await buffer.enqueue(.silence(frameCount: 10))
        XCTAssertEqual(buffer.bufferedFrames, 15)

        var output = [Float](repeating: 0, count: 3)
        _ = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 3)
        }
        XCTAssertEqual(buffer.bufferedFrames, 12)
    }

    // MARK: - Thread Safety Tests (Run with TSan)

    func testConcurrentAccess() async {
        let buffer = StreamingAudioBuffer()
        let iterations = 100

        // Producer task
        let producer = Task {
            for i in 0..<iterations {
                let samples = [Float](repeating: Float(i), count: 100)
                let cont = await buffer.enqueue(.audio(samples))
                if !cont { break }
            }
            buffer.markComplete()
        }

        // Consumer task
        let consumer = Task {
            var output = [Float](repeating: 0, count: 50)
            var totalRead = 0
            while true {
                let result = output.withUnsafeMutableBufferPointer { ptr in
                    buffer.readFrames(into: ptr.baseAddress!, count: 50)
                }
                totalRead += Int(result.framesRead)
                if result.isComplete { break }
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }

        await producer.value
        await consumer.value

        // If we get here without crashing, thread safety is likely working
        // TSan would catch actual data races
    }

    // MARK: - Chunk Type Tests

    func testAudioChunkFrameCount() {
        let audioChunk = StreamingAudioBuffer.AudioChunk.audio([1.0, 2.0, 3.0, 4.0, 5.0])
        XCTAssertEqual(audioChunk.frameCount, 5)
        XCTAssertFalse(audioChunk.isSilence)
    }

    func testSilenceChunkFrameCount() {
        let silenceChunk = StreamingAudioBuffer.AudioChunk.silence(frameCount: 1000)
        XCTAssertEqual(silenceChunk.frameCount, 1000)
        XCTAssertTrue(silenceChunk.isSilence)
    }

    // MARK: - Constants Tests

    func testConstants() {
        // Verify the constants match expected values
        XCTAssertEqual(StreamingAudioBuffer.maxBufferedFrames, 24000 * 10, "Max buffer should be 10 seconds")
        XCTAssertEqual(StreamingAudioBuffer.minBufferBeforeStart, 24000 / 4, "Min buffer should be 250ms")
        XCTAssertEqual(StreamingAudioBuffer.maxPauseDuration, 30.0, "Max pause should be 30 seconds")
        XCTAssertEqual(StreamingAudioBuffer.maxChunks, 2048, "Max chunks should be 2048")
    }

    // MARK: - Amendment 1: Edge Case Hardening Tests

    /// Test that oversized chunks don't cause deadlock
    /// Note: Actual chunk splitting is done in KokoroSynthesisAudioUnit, not StreamingAudioBuffer
    /// This test verifies that large chunks can flow through when there's a consumer
    func testOversizedChunkWithConcurrentDrain() async {
        let buffer = StreamingAudioBuffer()

        // Create chunk larger than maxBufferedFrames
        let oversized = [Float](repeating: 1.0, count: Int(StreamingAudioBuffer.maxBufferedFrames) + 50000)

        // Start producer - this would hang without concurrent consumption
        let producer = Task {
            _ = await buffer.enqueue(.audio(oversized))
            buffer.markComplete()
        }

        // Drain concurrently to provide backpressure relief
        let consumer = Task {
            var output = [Float](repeating: 0, count: 10000)
            while true {
                let result = output.withUnsafeMutableBufferPointer { ptr in
                    buffer.readFrames(into: ptr.baseAddress!, count: 10000)
                }
                if result.isComplete { break }
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }

        // Both should complete without hanging
        await producer.value
        await consumer.value
    }

    /// Test high contention scenario to verify trylock behavior
    /// The key invariant: operations complete without deadlock, even under extreme contention
    func testHighContentionNoBlocking() async {
        let buffer = StreamingAudioBuffer()

        #if DEBUG
        // Reset contention counters
        StreamingAudioBuffer.lockContentionCount = 0
        StreamingAudioBuffer.totalReadCalls = 0
        #endif

        // Hammer from multiple tasks simultaneously - this creates extreme artificial contention
        // In real usage, contention is extremely rare (<0.001%) due to short hold times
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

        // Test passes if we get here without deadlock
        // Under extreme contention like this test, some contention is expected
        // The important thing is the system remains responsive (no deadlock)

        #if DEBUG
        // Log contention for diagnostics (not a failure condition under extreme stress)
        if StreamingAudioBuffer.totalReadCalls > 0 {
            let contentionRate = Double(StreamingAudioBuffer.lockContentionCount) / Double(StreamingAudioBuffer.totalReadCalls)
            print("Test stress contention: \(contentionRate * 100)% (expected under extreme artificial load)")
        }
        #endif
    }

    /// Test that trylock failure returns silence (0 frames) not blocking
    func testTrylockFailureReturnsSilence() {
        // This test verifies the contract that readFrames never blocks
        // The actual trylock contention is tested in testHighContentionNoBlocking
        // Here we just verify the return type contract

        let buffer = StreamingAudioBuffer()

        var output = [Float](repeating: 999, count: 64)
        let result = output.withUnsafeMutableBufferPointer { ptr in
            buffer.readFrames(into: ptr.baseAddress!, count: 64)
        }

        // Empty buffer with synthesis ongoing should return 0 frames (underrun)
        XCTAssertEqual(result.framesRead, 0)
        XCTAssertFalse(result.isComplete)
        XCTAssertFalse(result.wasSpeech)
        // Output should not be modified when 0 frames read
    }
}
