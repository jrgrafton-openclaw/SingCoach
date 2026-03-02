import Foundation
import SwiftData

@Model
final class PracticeSession {
    var id: UUID
    var exerciseID: UUID
    var exerciseName: String
    var startTime: Date
    var durationSeconds: Double
    var date: Date // calendar day for grouping
    /// Exercise template ID — used to correlate with PracticeEntry for history display.
    /// Empty string for sessions created before this field was added.
    var templateID: String = ""
    
    init(exerciseID: UUID, exerciseName: String, durationSeconds: Double, templateID: String = "") {
        self.id = UUID()
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.startTime = Date()
        self.durationSeconds = durationSeconds
        self.templateID = templateID
        
        let calendar = Calendar.current
        self.date = calendar.startOfDay(for: Date())
    }
}