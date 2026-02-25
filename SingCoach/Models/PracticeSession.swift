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
    
    init(exerciseID: UUID, exerciseName: String, durationSeconds: Double) {
        self.id = UUID()
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.startTime = Date()
        self.durationSeconds = durationSeconds
        
        let calendar = Calendar.current
        self.date = calendar.startOfDay(for: Date())
    }
}