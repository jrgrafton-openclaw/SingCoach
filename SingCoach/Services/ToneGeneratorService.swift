import Foundation
import AVFoundation
import Combine

/// Plays a sine wave at a given frequency for pitch reference
@MainActor
final class ToneGeneratorService: ObservableObject {
    @Published var isPlaying = false
    
    private var audioEngine: AVAudioEngine?
    private var frequency: Double = 440
    private var autoStopTask: Task<Void, Never>?
    
    // Note names for display
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    /// Convert MIDI note number to frequency
    /// A4 = MIDI 69 = 440 Hz
    static func frequency(for midiNote: Int) -> Double {
        return 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
    
    /// Convert frequency to note name (e.g., "A4")
    static func noteName(for frequency: Double) -> String {
        guard frequency > 0 else { return "--" }
        let midiNote = Int(round(69 + 12 * log2(frequency / 440.0)))
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    /// Convert MIDI note to display name (e.g., "A4")
    static func noteName(for midiNote: Int) -> String {
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    /// All notes from C2 (MIDI 36) to C5 (MIDI 72)
    static let midiRange: ClosedRange<Int> = 36...72
    
    func play(midiNote: Int) {
        let freq = Self.frequency(for: midiNote)
        play(frequency: freq)
    }
    
    func play(frequency: Double) {
        // Cancel any existing auto-stop task
        autoStopTask?.cancel()
        autoStopTask = nil
        
        // Stop any existing tone first
        stop()
        
        self.frequency = frequency
        
        // Configure audio session first - do this on main thread
        let session = AVAudioSession.sharedInstance()
        do {
            // Use playAndRecord so it coexists with pitch detection mic input
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[ToneGenerator] Audio session error: \(error.localizedDescription)")
            // Continue anyway - the engine might still work
        }
        
        // Create new engine
        let newEngine = AVAudioEngine()
        
        let mainMixer = newEngine.mainMixerNode
        let outputFormat = newEngine.outputNode.inputFormat(forBus: 0)
        
        guard outputFormat.sampleRate > 0 else {
            print("[ToneGenerator] Invalid sample rate")
            return
        }
        
        let sampleRate = outputFormat.sampleRate
        
        // Create source node for sine wave - capture frequency safely
        let freq = self.frequency
        
        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseInc = 2.0 * Double.pi * freq / sampleRate
            
            var phase: Double = 0 // Local variable for this callback
            
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase))
                phase += phaseInc
                if phase > 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
                
                // Write to all channels
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample * 0.3 // 30% volume
                }
            }
            
            return noErr
        }
        
        newEngine.attach(sourceNode)
        newEngine.connect(sourceNode, to: mainMixer, format: outputFormat)
        
        do {
            try newEngine.start()
            self.audioEngine = newEngine
            self.isPlaying = true
            
            // Auto-stop after 1 second using Task
            autoStopTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if !Task.isCancelled {
                    self.stop()
                }
            }
        } catch {
            print("[ToneGenerator] Failed to start engine: \(error)")
        }
    }
    
    func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        
        audioEngine?.stop()
        audioEngine = nil
        isPlaying = false
    }
}