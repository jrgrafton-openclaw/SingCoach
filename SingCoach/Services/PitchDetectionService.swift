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
    private let bufferSize: AVAudioFrameCount = 4096
    
    // Note names
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    // Minimum/maximum frequencies to detect (human voice range)
    private let minFrequency: Double = 80   // ~E2
    private let maxFrequency: Double = 1000 // ~B5
    
    func start() async {
        guard !isDetecting else { return }
        
        // Request microphone permission first
        let granted = await requestMicrophonePermission()
        guard granted else {
            print("[PitchDetection] Microphone permission denied")
            return
        }
        
        do {
            // Use playAndRecord so tone generator and pitch detector coexist.
            // Use .default mode (not .measurement) — .measurement disables audio processing
            // but can cause conflicts on some devices when another engine is active.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[PitchDetection] Failed to configure audio session: \(error.localizedDescription)")
            return
        }
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let input = engine.inputNode
        inputNode = input
        
        let format = input.outputFormat(forBus: 0)
        
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            print("[PitchDetection] Invalid input format — mic may not be available in simulator")
            audioEngine = nil
            inputNode = nil
            return
        }
        
        // Install tap — the callback fires on an AVAudio internal thread (real-time, not main).
        //
        // IMPORTANT — iOS 26 / Swift 6 actor isolation crash:
        // The Swift 6 runtime injects an actor-isolation assertion at the POINT OF CLOSURE
        // CAPTURE, not just at the call site. If `self` (a @MainActor-isolated type) appears
        // in the closure capture list — even as `[weak self]` — the compiler emits a hidden
        // call to _swift_task_checkIsolatedSwift when the closure is *created* on the audio
        // thread. That check calls dispatch_assert_queue_fail → EXC_BREAKPOINT crash.
        //
        // Fix: wrap `self` in a nonisolated `AudioWeakRef` box before the closure, so the
        // closure captures only a plain nonisolated object. Hop to DispatchQueue.main.async
        // (NOT Task { @MainActor }) for the actual @MainActor work — DispatchQueue is safe
        // from any thread and carries no Swift Concurrency actor assertions.
        let ref = AudioWeakRef(self)
        let sr = format.sampleRate
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            // Copy samples out immediately — buffer is reused after this callback returns.
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
            DispatchQueue.main.async { ref.value?.handleSamples(samples, sampleRate: sr) }
        }
        
        do {
            try engine.start()
            isDetecting = true
        } catch {
            print("[PitchDetection] Failed to start engine: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            audioEngine = nil
            inputNode = nil
        }
    }
    
    func stop() {
        guard isDetecting else { return }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isDetecting = false
        currentPitch = nil
    }
    
    // MARK: - Test seam

    /// Injects raw samples directly into the pitch-detection pipeline.
    /// For unit tests only — allows testing the main-queue dispatch path without a real microphone.
    func injectSamplesForTesting(_ samples: [Float], sampleRate: Double) {
        handleSamples(samples, sampleRate: sampleRate)
    }

    // MARK: - Private helpers (all called on @MainActor)
    
    private func handleSamples(_ samples: [Float], sampleRate: Double) {
        guard let frequency = detectPitch(samples: samples, sampleRate: sampleRate),
              frequency >= minFrequency && frequency <= maxFrequency else { return }
        
        let midiNote = Int(round(69 + 12 * log2(frequency / 440.0)))
        let noteName = noteName(for: midiNote)
        let perfectFreq = Self.frequency(for: midiNote)
        let cents = 1200 * log2(frequency / perfectFreq)
        
        currentPitch = PitchResult(
            frequency: frequency,
            noteName: noteName,
            cents: cents,
            midiNote: midiNote
        )
    }
    
    private func requestMicrophonePermission() async -> Bool {
        // Use withTaskGroup to add a timeout — on simulator the callback may never fire
        // if there is no mic hardware, which would cause start() to hang indefinitely.
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
            group.addTask {
                // 3-second timeout fallback: treat as denied
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
    
    /// Autocorrelation-based pitch detection
    private func detectPitch(samples: [Float], sampleRate: Double) -> Double? {
        let n = samples.count
        guard n > 0 else { return nil }
        
        // Calculate autocorrelation
        let minLag = Int(sampleRate / maxFrequency) // ~44 samples for 1000Hz
        let maxLag = Int(sampleRate / minFrequency) // ~551 samples for 80Hz
        
        guard minLag < maxLag, maxLag < n / 2 else { return nil }
        
        var correlations: [Float] = []
        correlations.reserveCapacity(maxLag - minLag)
        
        for lag in minLag..<maxLag {
            var sum: Float = 0
            let limit = n - lag
            for i in 0..<limit {
                sum += samples[i] * samples[i + lag]
            }
            correlations.append(sum)
        }
        
        guard !correlations.isEmpty else { return nil }
        
        // Find the first peak (fundamental frequency)
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
        
        let y0 = Double(correlations[index - 1])
        let y1 = Double(correlations[index])
        let y2 = Double(correlations[index + 1])
        
        let denom = 2.0 * (y0 - 2.0 * y1 + y2)
        guard denom != 0 else { return sampleRate / Double(bestLag) }
        
        let refinedLag = Double(bestLag) + (y0 - y2) / denom
        
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
