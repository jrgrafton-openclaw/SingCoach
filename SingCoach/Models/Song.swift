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
        lessons.sorted { $0.date > $1.date }.first
    }
}
