import XCTest
import AVFoundation
@testable import SingCoach

/// Tests that verify audio callback closures are truly nonisolated and can
/// execute safely on non-main threads without triggering Swift 6 actor
/// isolation assertions (_swift_task_checkIsolatedSwift → EXC_BREAKPOINT).
///
/// These tests reproduce the exact crash scenario:
/// - A closure is invoked on a background thread (simulating AVAudio callback)
/// - If the closure carries @MainActor isolation, dispatch_assert_queue_fail fires
/// - If it's properly nonisolated, it runs without crashing
final class AudioCallbackIsolationTests: XCTestCase {

    // MARK: - makeAudioTapHandler isolation test

    /// Verify that the tap handler returned by makeAudioTapHandler() can be
    /// invoked on a background thread without crashing.
    /// This is the exact scenario that caused EXC_BREAKPOINT on iOS 26:
    /// AVAudioNodeTap fires the closure on an internal audio dispatch queue.
    func testTapHandlerRunsOnBackgroundThreadWithoutCrash() {
        let expectation = expectation(description: "handler called on main")

        var receivedSamples: [Float]?
        var receivedRate: Double?

        let handler = makeAudioTapHandler(sampleRate: 44100.0) { samples, rate in
            // This runs inside DispatchQueue.main.async (from makeAudioTapHandler)
            MainActor.assumeIsolated {
                receivedSamples = samples
                receivedRate = rate
                expectation.fulfill()
            }
        }

        // Simulate AVAudio tap: invoke handler on a background queue
        // If the closure is @MainActor-isolated, this would crash with
        // _swift_task_checkIsolatedSwift → dispatch_assert_queue_fail
        let audioQueue = DispatchQueue(label: "test.audio.tap", qos: .userInteractive)
        audioQueue.async {
            // Create a fake AVAudioPCMBuffer
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
                XCTFail("Could not create buffer")
                return
            }
            buffer.frameLength = 1024
            // Fill with a simple sine wave
            if let channelData = buffer.floatChannelData?[0] {
                for i in 0..<1024 {
                    channelData[i] = sin(Float(i) * 2.0 * .pi * 440.0 / 44100.0)
                }
            }
            let time = AVAudioTime(sampleTime: 0, atRate: 44100)
            handler(buffer, time)
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertNotNil(receivedSamples)
        XCTAssertEqual(receivedSamples?.count, 1024)
        XCTAssertEqual(receivedRate, 44100.0)
    }

    // MARK: - makeSineRenderBlock isolation test

    /// Verify that the render block returned by makeSineRenderBlock() can be
    /// invoked on a background thread without crashing.
    /// This simulates AURemoteIO::IOThread calling the render callback.
    func testRenderBlockRunsOnBackgroundThreadWithoutCrash() {
        let expectation = expectation(description: "render block completed")
        let phase = PhaseHolder()
        let phaseInc = 2.0 * Double.pi * 440.0 / 44100.0

        let renderBlock = makeSineRenderBlock(phaseHolder: phase, phaseIncrement: phaseInc)

        // Simulate AURemoteIO IOThread: invoke render block on a background queue
        let ioQueue = DispatchQueue(label: "test.auremoteio", qos: .userInteractive)
        ioQueue.async {
            // Allocate an AudioBufferList with one mono buffer
            let frameCount: UInt32 = 512
            let bytesPerFrame: UInt32 = UInt32(MemoryLayout<Float>.size)
            let dataSize = Int(frameCount * bytesPerFrame)
            let rawBuffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(frameCount))
            rawBuffer.initialize(repeating: 0, count: Int(frameCount))
            defer { rawBuffer.deallocate() }

            var audioBuffer = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: frameCount * bytesPerFrame,
                mData: UnsafeMutableRawPointer(rawBuffer)
            )

            withUnsafeMutablePointer(to: &audioBuffer) { bufPtr in
                var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: bufPtr.pointee)
                withUnsafeMutablePointer(to: &abl) { ablPtr in
                    var isSilence = ObjCBool(false)
                    var timestamp = AudioTimeStamp()
                    let status = renderBlock(
                        &isSilence,
                        &timestamp,
                        frameCount,
                        ablPtr
                    )
                    XCTAssertEqual(status, noErr)
                }
            }

            // Verify phase advanced (sine wave was generated)
            XCTAssertGreaterThan(phase.phase, 0)

            // Verify samples are non-zero (actual sine wave data)
            var hasNonZero = false
            for i in 0..<Int(frameCount) {
                if rawBuffer[i] != 0 {
                    hasNonZero = true
                    break
                }
            }
            XCTAssertTrue(hasNonZero, "Render block should have written non-zero samples")

            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    // MARK: - PhaseHolder thread safety

    /// PhaseHolder must be usable from a non-main thread without crashes.
    func testPhaseHolderIsNonisolated() {
        let expectation = expectation(description: "phase holder accessed")
        let phase = PhaseHolder()

        DispatchQueue.global().async {
            phase.phase = 1.234
            XCTAssertEqual(phase.phase, 1.234, accuracy: 0.001)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }
}
