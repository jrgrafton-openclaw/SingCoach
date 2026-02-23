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
    // AI Analysis fields (Build 28+)
    var aiAnalysis: String?      // JSON-encoded AIAnalysisResult
    var aiAnalysisDate: Date?    // when analysis was last run

    init(
        id: UUID = UUID(),
        songID: UUID,
        date: Date = Date(),
        audioFileURL: String,
        durationSeconds: Double = 0,
        transcript: String? = nil,
        transcriptionStatus: String = TranscriptionStatus.pending.rawValue,
        recordingType: String = "lesson",
        recommendedExercises: [Exercise] = [],
        aiAnalysis: String? = nil,
        aiAnalysisDate: Date? = nil
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
        self.aiAnalysis = aiAnalysis
        self.aiAnalysisDate = aiAnalysisDate
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
