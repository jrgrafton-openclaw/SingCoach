import Foundation
import SwiftData
import Combine

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 40)
    // Bug 6 fix: recordingDuration forwarded via Combine from recorder.$durationSeconds
    @Published var recordingDuration: Double = 0
    // Bug 5 fix: repurposed as showInlineRecorder (sheet removed, inline recorder used)
    @Published var showRecordingSheet = false

    let recorder = AudioRecordingService()

    private var currentFileURL: URL?
    private var currentRelativePath: String?
    private var song: Song?
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward waveform samples from recorder
        recorder.$waveformSamples
            .receive(on: RunLoop.main)
            .assign(to: &$waveformSamples)

        // Bug 6 fix: forward recording duration from recorder so GlobalRecordingBanner can show it
        recorder.$durationSeconds
            .receive(on: RunLoop.main)
            .assign(to: &$recordingDuration)
    }

    func configure(song: Song, modelContext: ModelContext) {
        self.song = song
        self.modelContext = modelContext
    }

    func startRecording(recordingType: String = "lesson") {
        guard let song else { return }
        do {
            let result = try recorder.startRecording(songID: song.id)
            currentFileURL = result.absoluteURL
            currentRelativePath = result.relativePath
            currentRecordingType = recordingType
            isRecording = true
            print("[SingCoach] RecordingVM: started recording for song \(song.title), type=\(recordingType), path=\(result.relativePath)")
        } catch {
            print("[SingCoach] Failed to start recording: \(error)")
        }
    }

    private(set) var currentRecordingType: String = "lesson"

    func stopRecording() async {
        guard let song, let modelContext, let fileURL = currentFileURL else { return }
        // Lesson 32: store relative path so recordings survive reinstall
        let storedPath = currentRelativePath ?? fileURL.absoluteString

        let duration = recorder.stopRecording()
        isRecording = false

        // Save the recording immediately — AI analysis is user-initiated via the Analyze button
        let lesson = Lesson(
            songID: song.id,
            audioFileURL: storedPath,
            durationSeconds: duration,
            transcriptionStatus: TranscriptionStatus.pending.rawValue,
            recordingType: currentRecordingType
        )
        song.lessons.append(lesson)
        modelContext.insert(lesson)
        try? modelContext.save()

        AnalyticsService.shared.lessonRecorded(durationSeconds: duration)
        print("[SingCoach] Recording saved (type=\(currentRecordingType)) — tap Analyze to get AI feedback")

        showRecordingSheet = false
    }
}
