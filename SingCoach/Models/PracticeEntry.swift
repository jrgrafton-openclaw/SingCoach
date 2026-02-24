import Foundation
import SwiftData

/// A single "I practiced this" event. Denormalised so entries survive lesson/exercise deletion.
@Model
final class PracticeEntry {
    var id: UUID
    var exerciseTemplateID: String   // for grouping/stats
    var exerciseName: String         // display — kept even if exercise is deleted
    var exerciseCategory: String     // for category stats
    var date: Date                   // when "Mark as Practiced" was tapped
    var lessonID: UUID?              // which recording triggered this recommendation (optional)

    init(
        id: UUID = UUID(),
        exerciseTemplateID: String,
        exerciseName: String,
        exerciseCategory: String,
        date: Date = Date(),
        lessonID: UUID? = nil
    ) {
        self.id = id
        self.exerciseTemplateID = exerciseTemplateID
        self.exerciseName = exerciseName
        self.exerciseCategory = exerciseCategory
        self.date = date
        self.lessonID = lessonID
    }
}
