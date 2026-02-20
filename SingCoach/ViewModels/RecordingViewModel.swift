import Foundation
import SwiftData
import Combine

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 40)
    @Published var recordingDuration: Double = 0
    @Published var transcriptionStatus: TranscriptionStatus = .pending
    @Published var showRecordingSheet = false

    let recorder = AudioRecordingService()
    private let transcriptionService = TranscriptionService()
    private let recommendationService = ExerciseRecommendationService()

    private var currentFileURL: URL?
    private var song: Song?
    private var modelContext: ModelContext?

    func configure(song: Song, modelContext: ModelContext) {
        self.song = song
        self.modelContext = modelContext
    }

    func startRecording() {
        guard let song else { return }
        do {
            let url = try recorder.startRecording(songID: song.id)
            currentFileURL = url
            isRecording = true
            print("[SingCoach] RecordingVM: started recording for song \(song.title)")
        } catch {
            print("[SingCoach] Failed to start recording: \(error)")
        }
    }

    func stopRecording() async {
        guard let song, let modelContext, let fileURL = currentFileURL else { return }

        let duration = recorder.stopRecording()
        isRecording = false

        let lesson = Lesson(
            songID: song.id,
            audioFileURL: fileURL.absoluteString,
            durationSeconds: duration,
            transcriptionStatus: TranscriptionStatus.pending.rawValue
        )
        song.lessons.append(lesson)
        modelContext.insert(lesson)
        try? modelContext.save()

        AnalyticsService.shared.lessonRecorded(durationSeconds: duration)
        print("[SingCoach] Lesson saved, starting transcription")

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
