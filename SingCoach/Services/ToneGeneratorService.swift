import Foundation
import AVFoundation
import Combine

/// Plays a sine wave at a given frequency for pitch reference
@MainActor
final class ToneGeneratorService: ObservableObject {
    @Published var isPlaying = false
    
    private var audioEngine: AVAudioEngine?
    private var oscillator: AVAudioSourceNode?
    private var phase: Double = 0
    private var frequency: Double = 440
    private let sampleRate: Double = 44100
    
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
        stop() // Stop any existing tone
        
        self.frequency = frequency
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let mainMixer = engine.mainMixerNode
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate
        
        // Create source node for sine wave
        var phase = 0.0
        let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
        
        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseInc = 2.0 * Double.pi * self.frequency / sampleRate
            
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase))
                phase += phaseInc
                if phase > 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
                
                // Write to all channels
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample * 0.5 // 50% volume
                }
            }
            
            return noErr
        }
        
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: outputFormat)
        
        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[ToneGenerator] Failed to set audio session: \(error)")
        }
        
        do {
            try engine.start()
            isPlaying = true
            
            // Auto-stop after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.stop()
            }
        } catch {
            print("[ToneGenerator] Failed to start engine: \(error)")
        }
    }
    
    func stop() {
        audioEngine?.stop()
        audioEngine = nil
        isPlaying = false
    }
}