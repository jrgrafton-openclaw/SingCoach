import Foundation
import SwiftData

/// Runs at app launch to retry any lessons that are stuck in a non-terminal state.
///
/// Handles three cases:
/// 1. `pending`   — saved but transcription never started (e.g. app killed before it ran)
/// 2. `processing` — app was killed mid-transcription; the state is now stale
/// 3. `failed`    — previous attempt errored; worth retrying once on the next launch
///
/// The caller is responsible for ensuring this runs *after* the ModelContainer is ready
/// and on @MainActor.
@MainActor
final class TranscriptionQueueService: ObservableObject {

    @Published var isRunning = false
    @Published var retranscribedCount = 0

    private let transcriptionService = TranscriptionService()

    /// Call once after ModelContainer is ready. Silently skips if speech permission not granted.
    func retryStuckLessons(context: ModelContext) {
        guard !isRunning else { return }
        isRunning = true
        Task {
            await _retryStuckLessons(context: context)
            isRunning = false
        }
    }

    private func _retryStuckLessons(context: ModelContext) async {
        // Fetch all non-performance lessons that are not in `done` state
        let allLessons: [Lesson]
        do {
            allLessons = try context.fetch(FetchDescriptor<Lesson>())
        } catch {
            print("[SingCoach] TranscriptionQueue: failed to fetch lessons: \(error)")
            return
        }

        // Heal any performances that are stuck as .pending (saved before the fix that sets
        // performances to .done immediately). Reset them to .done so they stop showing "Queued".
        var healedCount = 0
        for lesson in allLessons where lesson.isPerformance && lesson.status == .pending {
            lesson.transcriptionStatus = TranscriptionStatus.done.rawValue
            healedCount += 1
        }
        if healedCount > 0 {
            print("[SingCoach] TranscriptionQueue: healed \(healedCount) performance(s) stuck in pending")
            try? context.save()
        }

        let stuck = allLessons.filter { lesson in
            guard !lesson.isPerformance else { return false }
            let status = lesson.status
            return status == .pending || status == .processing || status == .failed
        }

        guard !stuck.isEmpty else {
            print("[SingCoach] TranscriptionQueue: no stuck lessons found")
            return
        }

        print("[SingCoach] TranscriptionQueue: found \(stuck.count) stuck lesson(s), checking permission...")

        // Check permission without prompting — only retry if already authorised
        let authStatus = SFSpeechRecognizerAuthorizationStatus.current
        if authStatus != .authorized {
            // Request permission (will show dialog if .notDetermined, no-op if .denied/.restricted)
            let granted = await transcriptionService.requestPermission()
            if !granted {
                print("[SingCoach] TranscriptionQueue: speech permission not granted, skipping retry")
                // Reset `processing` → `pending` so they show as "Queued" rather than a stuck spinner
                for lesson in stuck where lesson.status == .processing {
                    lesson.transcriptionStatus = TranscriptionStatus.pending.rawValue
                }
                try? context.save()
                return
            }
        }

        // Fetch exercises once for recommendation
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        var count = 0
        for lesson in stuck {
            let audioURL = AudioPathResolver.resolvedURL(lesson.audioFileURL)

            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                print("[SingCoach] TranscriptionQueue: audio file missing for lesson \(lesson.id), marking failed")
                lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
                try? context.save()
                continue
            }

            print("[SingCoach] TranscriptionQueue: retranscribing lesson \(lesson.id) (\(lesson.transcriptionStatus))")
            lesson.transcriptionStatus = TranscriptionStatus.processing.rawValue
            try? context.save()

            let result = await transcriptionService.transcribe(audioFileURL: audioURL)
            switch result {
            case .success(let transcript):
                lesson.transcript = transcript
                lesson.transcriptionStatus = TranscriptionStatus.done.rawValue

                // Re-run exercise recommendations if we have a song context
                let allSongs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
                if let song = allSongs.first(where: { $0.id == lesson.songID }) {
                    let recommender = ExerciseRecommendationService()
                    let recommended = await recommender.recommendAsync(
                        transcript: transcript,
                        song: song,
                        allExercises: allExercises
                    )
                    lesson.recommendedExercises = recommended
                }

                count += 1
                print("[SingCoach] TranscriptionQueue: lesson \(lesson.id) done (\(transcript.split(separator: " ").count) words)")

            case .failure(let error):
                lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
                print("[SingCoach] TranscriptionQueue: lesson \(lesson.id) failed: \(error)")
            }
            try? context.save()
        }

        retranscribedCount = count
        print("[SingCoach] TranscriptionQueue: complete. \(count)/\(stuck.count) lessons retranscribed.")
    }
}

// MARK: - Authorization status helper (synchronous check without prompting)

import Speech

extension SFSpeechRecognizerAuthorizationStatus {
    static var current: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
}
