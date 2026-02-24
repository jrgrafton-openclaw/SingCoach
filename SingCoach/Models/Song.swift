import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID
    var title: String
    var artist: String
    @Relationship(deleteRule: .cascade) var lyricsLines: [LyricsLine]
    var artworkURL: String?
    var appleMusicID: String?
    var karaokeAppleMusicID: String?
    var karaokeOverrideByUser: Bool
    var karaokeTrackID: String?       // MusicKit Song.id for selected karaoke track
    var karaokeTrackTitle: String?    // Display name of matched karaoke track
    var karaokeSearchStatus: String   // "idle" | "searching" | "found" | "not_found"
    @Relationship(deleteRule: .cascade) var lessons: [Lesson]
    @Relationship(deleteRule: .cascade) var exercises: [Exercise]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        lyricsLines: [LyricsLine] = [],
        artworkURL: String? = nil,
        appleMusicID: String? = nil,
        karaokeAppleMusicID: String? = nil,
        karaokeOverrideByUser: Bool = false,
        karaokeTrackID: String? = nil,
        karaokeTrackTitle: String? = nil,
        karaokeSearchStatus: String = "idle",
        lessons: [Lesson] = [],
        exercises: [Exercise] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.lyricsLines = lyricsLines
        self.artworkURL = artworkURL
        self.appleMusicID = appleMusicID
        self.karaokeAppleMusicID = karaokeAppleMusicID
        self.karaokeOverrideByUser = karaokeOverrideByUser
        self.karaokeTrackID = karaokeTrackID
        self.karaokeTrackTitle = karaokeTrackTitle
        self.karaokeSearchStatus = karaokeSearchStatus
        self.lessons = lessons
        self.exercises = exercises
        self.createdAt = createdAt
    }

    var sortedLyricsLines: [LyricsLine] {
        lyricsLines.sorted { $0.index < $1.index }
    }

    var hasSyncedLyrics: Bool {
        lyricsLines.contains { $0.timestampSeconds != nil }
    }

    var mostRecentLesson: Lesson? {
        lessons.filter { !$0.isPerformance }.sorted { $0.date > $1.date }.first
    }

    /// Most recent recording of ANY type (lesson or performance) that has AI-recommended exercises.
    /// Used by PracticeView so performance recordings also populate the practice tab.
    var mostRecentRecordingWithExercises: Lesson? {
        lessons.sorted { $0.date > $1.date }.first { !$0.recommendedExercises.isEmpty }
    }
}
