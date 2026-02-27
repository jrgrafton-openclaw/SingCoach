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
        // Cancel any pending auto-stop before touching the engine
        autoStopTask?.cancel()
        autoStopTask = nil
        
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
        
        // Reset phase for clean start
        phaseHolder.phase = 0
        let phaseRef = phaseHolder  // capture the holder, not self — avoids retain cycle and is callback-safe
        
        // IMPORTANT: The AVAudioSourceNode render block fires on a real-time audio thread.
        // On iOS 26+ Swift 6 runtime, if this closure implicitly captures `@MainActor`-isolated
        // state (even indirectly through `self`), Swift injects an actor isolation check
        // (_swift_task_checkIsolatedSwift → dispatch_assert_queue_fail → EXC_BREAKPOINT crash).
        //
        // Fix: only capture plain non-isolated values (phaseRef: PhaseHolder class, phaseInc: Double).
        // PhaseHolder is a non-isolated private class — safe to mutate from the audio thread.
        // Never reference `self` or any @MainActor property inside this block.
        let node = AVAudioSourceNode { [phaseRef, phaseInc] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phaseRef.phase)) * 0.3
                phaseRef.phase += phaseInc
                if phaseRef.phase > 2.0 * Double.pi {
                    phaseRef.phase -= 2.0 * Double.pi
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
        
        newEngine.attach(node)
        newEngine.connect(node, to: mainMixer, format: outputFormat)
        
        do {
            try newEngine.start()
            self.audioEngine = newEngine
            self.sourceNode = node
            self.isPlaying = true
            
            // Auto-stop after 1 second
            autoStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            print("[ToneGenerator] Failed to start engine: \(error)")
            newEngine.detach(node)
        }
    }
    
    func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        tearDownEngine()
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
private final class PhaseHolder {
    var phase: Double = 0
}
