import Foundation
import AVFoundation
import Combine

@MainActor
protocol AudioRecordingProtocol: AnyObject {
    var isRecording: Bool { get }
    var currentAmplitude: Float { get }
    var durationSeconds: Double { get }
    func startRecording(songID: UUID) throws -> (absoluteURL: URL, relativePath: String)
    func stopRecording() -> Double
}

@MainActor
final class AudioRecordingService: NSObject, ObservableObject, AudioRecordingProtocol {
    @Published var isRecording = false
    @Published var currentAmplitude: Float = 0.0
    @Published var durationSeconds: Double = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var startTime: Date?

    private var amplitudeHistory: [Float] = Array(repeating: 0.0, count: 40)
    var amplitudeSamples: [Float] { amplitudeHistory }

    @Published var waveformSamples: [Float] = Array(repeating: 0.0, count: 40)

    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
        print("[SingCoach] AudioSession configured: playAndRecord")
    }

    /// Returns the *relative* path stored in SwiftData (e.g. "Lessons/<songID>/lesson_<uuid>.m4a").
    /// Lesson 32: never store absolute paths — container UUID changes on reinstall.
    func startRecording(songID: UUID) throws -> (absoluteURL: URL, relativePath: String) {
        try setupAudioSession()

        let lessonsDir = try lessonsDirectory(songID: songID)
        let fileName = "lesson_\(UUID().uuidString).m4a"
        let fileURL = lessonsDir.appendingPathComponent(fileName)
        let relativePath = "Lessons/\(songID.uuidString)/\(fileName)"

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        audioRecorder?.record()

        startTime = Date()
        isRecording = true

        // Set up amplitude monitoring.
        // IMPORTANT: Timer callbacks fire on the run-loop thread (usually main), but
        // `Task { @MainActor }` from inside a Timer callback can trigger Swift 6 actor
        // isolation assertions on iOS 26+ → EXC_BREAKPOINT crash.
        // Use DispatchQueue.main.async instead — it is always safe from any thread.
        let ref = AudioWeakRef(self)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async { ref.value?.updateAmplitude() }
        }

        print("[SingCoach] Recording started: \(relativePath)")
        return (fileURL, relativePath)
    }

    func stopRecording() -> Double {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        audioRecorder?.stop()
        audioRecorder = nil   // release the recorder so AVFoundation can close the file
        timer?.invalidate()
        timer = nil
        isRecording = false
        durationSeconds = duration
        waveformSamples = Array(repeating: 0, count: 40)
        // Deactivate the recording session so SFSpeechURLRecognitionRequest can start cleanly.
        // Leaving a .playAndRecord session active while speech recognition starts causes
        // session conflicts and an EXC_CRASH on some iOS builds.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[SingCoach] Recording stopped, duration=\(duration)s, session deactivated")
        return duration
    }

    private func updateAmplitude() {
        guard isRecording else { return }
        audioRecorder?.updateMeters()
        let power = audioRecorder?.averagePower(forChannel: 0) ?? -160
        // Normalise from -60dB..0dB to 0..1
        let normalized = max(0, min(1, (power + 60) / 60))
        currentAmplitude = normalized
        durationSeconds = startTime.map { Date().timeIntervalSince($0) } ?? 0

        amplitudeHistory.removeFirst()
        amplitudeHistory.append(normalized)
        waveformSamples = amplitudeHistory
    }

    private func lessonsDirectory(songID: UUID) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Lessons/\(songID.uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

extension AudioRecordingService: @preconcurrency AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("[SingCoach] Recorder finished, success=\(flag)")
    }
}
