import Foundation
import AVFoundation
import Combine

/// Detects pitch from microphone input using autocorrelation
@MainActor
final class PitchDetectionService: ObservableObject {
    @Published var isDetecting = false
    @Published var currentPitch: PitchResult?
    
    struct PitchResult {
        let frequency: Double
        let noteName: String
        let cents: Double // deviation from true pitch (-50 to +50)
        let midiNote: Int
        
        var isInTune: Bool {
            return abs(cents) <= 10
        }
    }
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let sampleRate: Double = 44100
    private let bufferSize: AVAudioFrameCount = 4096
    
    // Note names
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    // Minimum/maximum frequencies to detect (human voice range)
    private let minFrequency: Double = 80   // ~E2
    private let maxFrequency: Double = 1000 // ~B5
    
    func start() async throws {
        guard !isDetecting else { return }
        
        // Request microphone permission
        let status = await requestMicrophonePermission()
        guard status else {
            throw PitchDetectionError.microphonePermissionDenied
        }
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        inputNode = engine.inputNode
        guard let input = inputNode else { return }
        
        let format = input.outputFormat(forBus: 0)
        
        // Install tap on input node
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        
        try engine.start()
        isDetecting = true
    }
    
    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isDetecting = false
        currentPitch = nil
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Run pitch detection on background thread
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        if let frequency = detectPitch(samples: samples), 
           frequency >= minFrequency && frequency <= maxFrequency {
            
            let midiNote = Int(round(69 + 12 * log2(frequency / 440.0)))
            let noteName = noteName(for: midiNote)
            let perfectFreq = Self.frequency(for: midiNote)
            let cents = 1200 * log2(frequency / perfectFreq)
            
            let result = PitchResult(
                frequency: frequency,
                noteName: noteName,
                cents: cents,
                midiNote: midiNote
            )
            
            Task { @MainActor [weak self] in
                self?.currentPitch = result
            }
        }
    }
    
    /// Autocorrelation-based pitch detection
    private func detectPitch(samples: [Float]) -> Double? {
        let n = samples.count
        guard n > 0 else { return nil }
        
        // Calculate autocorrelation
        var correlations: [Float] = []
        let minLag = Int(sampleRate / maxFrequency) // ~44 samples for 1000Hz
        let maxLag = Int(sampleRate / minFrequency) // ~551 samples for 80Hz
        
        for lag in minLag..<min(maxLag, n / 2) {
            var sum: Float = 0
            for i in 0..<(n - lag) {
                sum += samples[i] * samples[i + lag]
            }
            correlations.append(sum)
        }
        
        // Find the first peak (fundamental frequency)
        guard !correlations.isEmpty else { return nil }
        
        var maxCorrelation: Float = 0
        var bestLag = minLag
        
        for i in 1..<(correlations.count - 1) {
            if correlations[i] > correlations[i - 1] && 
               correlations[i] > correlations[i + 1] &&
               correlations[i] > maxCorrelation {
                maxCorrelation = correlations[i]
                bestLag = minLag + i
            }
        }
        
        // Require sufficient correlation (not noise)
        guard maxCorrelation > 0.1 else { return nil }
        
        // Parabolic interpolation for better precision
        let index = bestLag - minLag
        guard index > 0 && index < correlations.count - 1 else {
            return sampleRate / Double(bestLag)
        }
        
        let y0 = correlations[index - 1]
        let y1 = correlations[index]
        let y2 = correlations[index + 1]
        
        let refinedLag = Double(bestLag) + Double(y0 - y2) / (2 * Double(y0 - 2 * y1 + y2))
        
        return sampleRate / refinedLag
    }
    
    private func noteName(for midiNote: Int) -> String {
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    private static func frequency(for midiNote: Int) -> Double {
        return 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
}

enum PitchDetectionError: LocalizedError {
    case microphonePermissionDenied
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required for pitch detection."
        }
    }
}