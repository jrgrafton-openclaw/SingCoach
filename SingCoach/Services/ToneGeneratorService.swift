import Foundation
import AVFoundation
import Combine

/// Plays a sine wave at a given frequency for pitch reference
@MainActor
final class ToneGeneratorService: ObservableObject {
    @Published var isPlaying = false
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var autoStopTask: Task<Void, Never>?
    
    // Atomic phase tracker shared with audio callback — protected by being a class
    private let phaseHolder = PhaseHolder()
    private var envelopeHolder = EnvelopeHolder()
    private var fadeOutTask: Task<Void, Never>?
    
    // Note names for display — nonisolated so they can be called from any context (tests, SwiftUI, etc.)
    nonisolated static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    /// Convert MIDI note number to frequency. A4 = MIDI 69 = 440 Hz
    nonisolated static func frequency(for midiNote: Int) -> Double {
        return 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
    
    /// Convert frequency to note name (e.g., "A4")
    nonisolated static func noteName(for frequency: Double) -> String {
        guard frequency > 0 else { return "--" }
        let midiNote = Int(round(69 + 12 * log2(frequency / 440.0)))
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    /// Convert MIDI note to display name (e.g., "A4")
    nonisolated static func noteName(for midiNote: Int) -> String {
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    /// All notes from C2 (MIDI 36) to C5 (MIDI 72)
    nonisolated static let midiRange: ClosedRange<Int> = 36...72
    
    func play(midiNote: Int) {
        let freq = Self.frequency(for: midiNote)
        play(frequency: freq)
    }
    
    func play(frequency: Double) {
        // Cancel any pending auto-stop / fade-out before touching the engine
        autoStopTask?.cancel()
        autoStopTask = nil
        fadeOutTask?.cancel()
        fadeOutTask = nil
        
        // Tear down existing engine cleanly before creating a new one
        tearDownEngine()
        
        // Configure audio session — must match PitchDetectionService's .playAndRecord category
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[ToneGenerator] Audio session error: \(error.localizedDescription)")
            // Continue — engine may still work
        }
        
        let newEngine = AVAudioEngine()
        let mainMixer = newEngine.mainMixerNode
        let outputFormat = newEngine.outputNode.inputFormat(forBus: 0)
        
        guard outputFormat.sampleRate > 0 else {
            print("[ToneGenerator] Invalid sample rate — skipping playback")
            return
        }
        
        let sampleRate = outputFormat.sampleRate
        let phaseInc = 2.0 * Double.pi * frequency / sampleRate
        
        // Reset phase and envelope for clean start
        phaseHolder.phase = 0
        let newEnvelope = EnvelopeHolder()
        envelopeHolder = newEnvelope
        let phaseRef = phaseHolder  // capture the holder, not self — avoids retain cycle and is callback-safe
        
        // CRITICAL — iOS 26 / Swift 6 actor isolation crash:
        // Any closure defined inside a @MainActor method inherits @MainActor isolation
        // in its compiler-generated thunk, REGARDLESS of captures. When the thunk runs
        // on the AURemoteIO audio thread → _swift_task_checkIsolatedSwift →
        // dispatch_assert_queue_fail → EXC_BREAKPOINT crash.
        //
        // FIX: The render block is created by makePianoRenderBlock() — a nonisolated free
        // function in AudioCallbacks.swift. Its closure carries NO actor annotation.
        let renderBlock = makePianoRenderBlock(
            phaseHolder: phaseRef,
            phaseIncrement: phaseInc,
            envelopeHolder: newEnvelope,
            sampleRate: sampleRate
        )
        let node = AVAudioSourceNode(renderBlock: renderBlock)
        
        newEngine.attach(node)
        newEngine.connect(node, to: mainMixer, format: outputFormat)
        
        do {
            try newEngine.start()
            self.audioEngine = newEngine
            self.sourceNode = node
            self.isPlaying = true
            
            // Auto-stop after 1 second — initiate fade-out 50ms before teardown
            autoStopTask = Task { @MainActor [weak self] in
                // Play for ~950ms, then start a 50ms fade-out, then tear down
                try? await Task.sleep(nanoseconds: 950_000_000)
                guard !Task.isCancelled else { return }
                self?.beginFadeOut()
            }
        } catch {
            print("[ToneGenerator] Failed to start engine: \(error)")
            newEngine.detach(node)
        }
    }
    
    /// Triggers a smooth fade-out on the audio thread, then tears down the engine.
    private func beginFadeOut() {
        let fadeMs: Double = 50 // 50ms fade — eliminates click
        let sampleRate = audioEngine?.outputNode.inputFormat(forBus: 0).sampleRate ?? 44100
        let fadeSamples = Int(fadeMs / 1000.0 * sampleRate)
        envelopeHolder.startFadeOut(samples: fadeSamples)
        
        fadeOutTask = Task { @MainActor [weak self] in
            // Wait for the fade-out to complete + a small margin
            try? await Task.sleep(nanoseconds: UInt64(fadeMs * 1_500_000)) // 1.5x the fade duration
            guard !Task.isCancelled else { return }
            self?.tearDownEngine()
        }
    }
    
    func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        fadeOutTask?.cancel()
        fadeOutTask = nil
        // If currently playing, fade out gracefully; otherwise just tear down.
        // Set isPlaying = false immediately so callers see the state change right away.
        if isPlaying && audioEngine != nil {
            isPlaying = false
            beginFadeOut()
        } else {
            tearDownEngine()
        }
    }
    
    private func tearDownEngine() {
        guard let engine = audioEngine else { return }
        
        // Detach source node first to stop the render callback from firing
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        
        engine.stop()
        audioEngine = nil
        isPlaying = false
    }
}

/// Holds a mutable phase value that can be safely captured by the AVAudioSourceNode render callback.
/// Using a class (reference type) avoids data races from value-type captures.
/// Internal (not private) so AudioCallbacks.swift can reference it.
final class PhaseHolder: @unchecked Sendable {
    var phase: Double = 0
}
