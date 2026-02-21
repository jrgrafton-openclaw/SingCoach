import Foundation
import SwiftData
import Combine

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 40)
    // Bug 6 fix: recordingDuration forwarded via Combine from recorder.$durationSeconds
    @Published var recordingDuration: Double = 0
    @Published var transcriptionStatus: TranscriptionStatus = .pending
    // Bug 5 fix: repurposed as showInlineRecorder (sheet removed, inline recorder used)
    @Published var showRecordingSheet = false

    let recorder = AudioRecordingService()
    private let transcriptionService = TranscriptionService()
    private let recommendationService = ExerciseRecommendationService()

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
        print("[SingCoach] Lesson saved (type=\(currentRecordingType)), starting transcription")

        // Skip transcription for performances
        guard currentRecordingType != "performance" else {
            showRecordingSheet = false
            return
        }

        // Ensure speech permission before transcribing (silent failure if not granted)
        let permissionGranted = await transcriptionService.requestPermission()
        guard permissionGranted else {
            lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
            transcriptionStatus = .failed
            print("[SingCoach] Transcription skipped — speech recognition permission denied")
            try? modelContext.save()
            return
        }

        // Start transcription
        lesson.transcriptionStatus = TranscriptionStatus.processing.rawValue
        try? modelContext.save()
        transcriptionStatus = .processing

        let result = await transcriptionService.transcribe(audioFileURL: fileURL)
        switch result {
        case .success(let transcript):
            lesson.transcript = transcript
            lesson.transcriptionStatus = TranscriptionStatus.done.rawValue
            transcriptionStatus = .done

            let wordCount = transcript.split(separator: " ").count
            AnalyticsService.shared.lessonTranscribed(success: true, wordCount: wordCount)

            // Recommend exercises
            let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
            let recommended = recommendationService.recommendExercises(
                transcript: transcript,
                song: song,
                allExercises: allExercises
            )
            lesson.recommendedExercises = recommended

        case .failure(let error):
            lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
            transcriptionStatus = .failed
            AnalyticsService.shared.lessonTranscribed(success: false, wordCount: 0)
            print("[SingCoach] Transcription failed: \(error)")
        }

        try? modelContext.save()
        showRecordingSheet = false
    }
}
