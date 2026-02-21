import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID
    var templateID: String?
    var name: String
    var category: String
    var exerciseDescription: String
    var instruction: String
    var focusArea: String
    var isPinned: Bool
    var youtubeURL: String?
    var durationMinutes: Int
    var difficulty: String
    var tips: [String]
    var keywords: [String]
    var createdAt: Date
    var isUserCreated: Bool  // FEATURE 3: distinguish user-created from library exercises
    var songID: UUID?        // FEATURE 3: link to a specific song (nil = library exercise)

    init(
        id: UUID = UUID(),
        templateID: String? = nil,
        name: String,
        category: String,
        exerciseDescription: String,
        instruction: String,
        focusArea: String,
        isPinned: Bool = false,
        youtubeURL: String? = nil,
        durationMinutes: Int = 5,
        difficulty: String = "beginner",
        tips: [String] = [],
        keywords: [String] = [],
        createdAt: Date = Date(),
        isUserCreated: Bool = false,
        songID: UUID? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.category = category
        self.exerciseDescription = exerciseDescription
        self.instruction = instruction
        self.focusArea = focusArea
        self.isPinned = isPinned
        self.youtubeURL = youtubeURL
        self.durationMinutes = durationMinutes
        self.difficulty = difficulty
        self.tips = tips
        self.keywords = keywords
        self.createdAt = createdAt
        self.isUserCreated = isUserCreated
        self.songID = songID
    }
}

enum ExerciseCategory: String, CaseIterable {
    case breath = "breath"
    case pitch = "pitch"
    case resonance = "resonance"
    case agility = "agility"
    case register = "register"
    case vowel = "vowel"
    case articulation = "articulation"
    case warmup = "warmup"

    var displayName: String {
        switch self {
        case .breath: return "Breath"
        case .pitch: return "Pitch"
        case .resonance: return "Resonance"
        case .agility: return "Agility"
        case .register: return "Register"
        case .vowel: return "Vowel"
        case .articulation: return "Articulation"
        case .warmup: return "Warm-up"
        }
    }

    var sfSymbol: String {
        switch self {
        case .breath: return "wind"
        case .pitch: return "waveform.path"
        case .resonance: return "waveform"
        case .agility: return "hare"
        case .register: return "slider.vertical.3"
        case .vowel: return "mouth"
        case .articulation: return "textformat.abc"
        case .warmup: return "flame"
        }
    }
}

enum Difficulty: String, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"

    var color: String {
        switch self {
        case .beginner: return "#4CAF50"
        case .intermediate: return "#FF9800"
        case .advanced: return "#F44336"
        }
    }
}
