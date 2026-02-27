import AVFoundation

// ============================================================================
// WHY THIS FILE EXISTS — iOS 26 / Swift 6 Actor Isolation Crash
// ============================================================================
//
// On iOS 26+ with the Swift 6 runtime, any closure defined inside a @MainActor
// method INHERITS @MainActor isolation — even if it captures zero @MainActor
// state. The Swift compiler emits a hidden thunk that calls
// _swift_task_checkIsolatedSwift before or when the closure executes.
//
// When that closure runs on a non-main thread (AVAudio tap, AVAudioSourceNode
// render block, AURemoteIO IOThread), the check fires:
//   dispatch_assert_queue_fail → EXC_BREAKPOINT crash.
//
// Previous fix attempts tried:
//   1. [weak self] → still crashes (closure context inherits @MainActor)
//   2. Unmanaged.passUnretained → still crashes + use-after-free risk
//   3. AudioWeakRef wrapper → still crashes (closure context, not captures)
//
// THE ACTUAL FIX: Define the closure in a nonisolated context. A nonisolated
// free function or static method produces a closure that carries NO actor
// annotation. The compiler does NOT inject isolation checks into its thunk.
//
// These functions are called from @MainActor methods, but the closures they
// RETURN are nonisolated. The @MainActor caller passes in only plain values
// (no @MainActor-isolated types cross the boundary).
// ============================================================================

/// Creates an AVAudioNode tap closure that copies samples and dispatches to main.
/// The returned closure is nonisolated — safe to run on any audio thread.
///
/// - Parameters:
///   - handler: Called on the main queue with copied samples and sample rate.
///              Use `[weak self]` in the caller when creating this handler.
nonisolated func makeAudioTapHandler(
    sampleRate: Double,
    handler: @escaping @Sendable ([Float], Double) -> Void
) -> ((AVAudioPCMBuffer, AVAudioTime) -> Void) {
    return { buffer, _ in
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        DispatchQueue.main.async {
            handler(samples, sampleRate)
        }
    }
}

/// Creates an AVAudioSourceNode render block that generates a sine wave.
/// The returned block is nonisolated — safe to run on the AURemoteIO thread.
///
/// - Parameters:
///   - phaseHolder: Mutable phase state (nonisolated class, thread-safe by design).
///   - phaseIncrement: Radians per sample (2π × frequency / sampleRate).
nonisolated func makeSineRenderBlock(
    phaseHolder: PhaseHolder,
    phaseIncrement: Double
) -> AVAudioSourceNodeRenderBlock {
    return { _, _, frameCount, audioBufferList -> OSStatus in
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(phaseHolder.phase)) * 0.3
            phaseHolder.phase += phaseIncrement
            if phaseHolder.phase > 2.0 * Double.pi {
                phaseHolder.phase -= 2.0 * Double.pi
            }
            for buffer in ablPointer {
                let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                if frame < buf.count {
                    buf[frame] = sample
                }
            }
        }
        return noErr
    }
}
