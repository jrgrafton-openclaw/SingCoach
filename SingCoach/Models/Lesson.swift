import Foundation
import SwiftData

@Model
final class Lesson {
    var id: UUID
    var songID: UUID
    var date: Date
    var audioFileURL: String
    var durationSeconds: Double
    var transcript: String?
    var transcriptionStatus: String
    var recordingType: String  // "lesson" or "performance" — FEATURE 1
    @Relationship(deleteRule: .nullify) var recommendedExercises: [Exercise]

    init(
        id: UUID = UUID(),
        songID: UUID,
        date: Date = Date(),
        audioFileURL: String,
        durationSeconds: Double = 0,
        transcript: String? = nil,
        transcriptionStatus: String = TranscriptionStatus.pending.rawValue,
        recordingType: String = "lesson",
        recommendedExercises: [Exercise] = []
    ) {
        self.id = id
        self.songID = songID
        self.date = date
        self.audioFileURL = audioFileURL
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.transcriptionStatus = transcriptionStatus
        self.recordingType = recordingType
        self.recommendedExercises = recommendedExercises
    }

    var status: TranscriptionStatus {
        TranscriptionStatus(rawValue: transcriptionStatus) ?? .pending
    }

    var isPerformance: Bool {
        recordingType == "performance"
    }
}

enum TranscriptionStatus: String, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case done = "done"
    case failed = "failed"

    var displayText: String {
        switch self {
        case .pending: return "Queued"
        case .processing: return "Transcribing..."
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}
