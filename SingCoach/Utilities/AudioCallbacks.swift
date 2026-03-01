import AVFoundation

/// Tracks envelope state for the piano tone generator.
/// Like PhaseHolder, this is a reference type captured by the render callback.
final class EnvelopeHolder: @unchecked Sendable {
    var sampleIndex: Int = 0
    var isFadingOut: Bool = false
    var fadeSamplesRemaining: Int = 0
    var fadeTotalSamples: Int = 0
    
    /// Begin a fade-out over the given number of samples.
    func startFadeOut(samples: Int) {
        isFadingOut = true
        fadeSamplesRemaining = samples
        fadeTotalSamples = samples
    }
}

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

/// Creates an AVAudioSourceNode render block that generates a piano-like tone
/// with harmonics and an ADSR envelope for a natural, warm sound.
/// The returned block is nonisolated — safe to run on the AURemoteIO thread.
///
/// - Parameters:
///   - phaseHolder: Mutable phase state (nonisolated class, thread-safe by design).
///   - phaseIncrement: Radians per sample for fundamental (2π × frequency / sampleRate).
///   - envelopeHolder: Tracks the current sample index for envelope shaping.
///   - sampleRate: Audio sample rate for envelope timing.
nonisolated func makePianoRenderBlock(
    phaseHolder: PhaseHolder,
    phaseIncrement: Double,
    envelopeHolder: EnvelopeHolder,
    sampleRate: Double
) -> AVAudioSourceNodeRenderBlock {
    // Harmonic ratios and relative amplitudes for a piano-like timbre.
    // Fundamental + 4 partials with exponentially decaying amplitudes.
    let harmonics: [(multiplier: Double, amplitude: Double)] = [
        (1.0, 1.0),    // fundamental
        (2.0, 0.5),    // 2nd harmonic
        (3.0, 0.25),   // 3rd harmonic
        (4.0, 0.10),   // 4th harmonic
        (5.0, 0.05),   // 5th harmonic
    ]
    let normalisationFactor = 1.0 / harmonics.reduce(0.0) { $0 + $1.amplitude }
    let masterGain: Double = 0.35
    
    // Envelope timing (in samples)
    let attackSamples = Int(0.005 * sampleRate)   // 5ms attack — fast like a piano hammer
    let decaySamples = Int(0.15 * sampleRate)     // 150ms decay to sustain level
    let sustainLevel: Double = 0.6                 // sustain at 60% of peak
    
    return { _, _, frameCount, audioBufferList -> OSStatus in
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frameCount) {
            let sampleIndex = envelopeHolder.sampleIndex
            
            // ADSR envelope (no release here — release is handled by the fade-out)
            let envelope: Double
            if sampleIndex < attackSamples {
                // Attack: ramp up
                envelope = Double(sampleIndex) / Double(attackSamples)
            } else if sampleIndex < attackSamples + decaySamples {
                // Decay: exponential fall to sustain level
                let decayProgress = Double(sampleIndex - attackSamples) / Double(decaySamples)
                envelope = 1.0 - (1.0 - sustainLevel) * decayProgress
            } else {
                // Sustain
                envelope = sustainLevel
            }
            
            // Check if we're in fade-out mode
            let fadeGain: Double
            if envelopeHolder.isFadingOut {
                let fadeRemaining = envelopeHolder.fadeSamplesRemaining
                if fadeRemaining <= 0 {
                    // Fade complete — output silence
                    for buffer in ablPointer {
                        let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                        if frame < buf.count { buf[frame] = 0 }
                    }
                    envelopeHolder.sampleIndex += 1
                    continue
                }
                fadeGain = Double(fadeRemaining) / Double(envelopeHolder.fadeTotalSamples)
                envelopeHolder.fadeSamplesRemaining -= 1
            } else {
                fadeGain = 1.0
            }
            
            // Sum harmonics
            var sample: Double = 0
            for h in harmonics {
                sample += sin(phaseHolder.phase * h.multiplier) * h.amplitude
            }
            sample *= normalisationFactor * envelope * masterGain * fadeGain
            
            let floatSample = Float(sample)
            
            phaseHolder.phase += phaseIncrement
            if phaseHolder.phase > 2.0 * Double.pi {
                phaseHolder.phase -= 2.0 * Double.pi
            }
            envelopeHolder.sampleIndex += 1
            
            for buffer in ablPointer {
                let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                if frame < buf.count {
                    buf[frame] = floatSample
                }
            }
        }
        return noErr
    }
}
