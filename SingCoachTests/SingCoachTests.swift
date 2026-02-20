import XCTest
import SwiftData
@testable import SingCoach

@MainActor
final class SingCoachTests: XCTestCase {

    // MARK: - App Metadata
    func testAppDisplayNameIsCorrect() {
        let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        XCTAssertEqual(displayName, "SingCoach")
    }

    // MARK: - LRC Lyrics Parser
    func testLRCParserParsesTimestamps() {
        let lrc = """
[00:01.23] First line
[00:05.50] Second line
[00:10.00] Third line
"""
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics(lrc)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[0].timestampSeconds ?? 0, 1.23, accuracy: 0.01)
        XCTAssertEqual(lines[1].text, "Second line")
        XCTAssertEqual(lines[1].timestampSeconds ?? 0, 5.50, accuracy: 0.01)
        XCTAssertEqual(lines[2].timestampSeconds ?? 0, 10.00, accuracy: 0.01)
    }

    func testLRCParserPlainTextFallback() {
        let plain = """
First line
Second line
Third line
"""
        let service = LRCLibService.shared
        let lines = service.parsePlainLyrics(plain)

        XCTAssertEqual(lines.count, 3)
        XCTAssertNil(lines[0].timestampSeconds)
        XCTAssertEqual(lines[0].text, "First line")
    }

    func testLRCParserEmptyInput() {
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics("")
        XCTAssertEqual(lines.count, 0)
    }

    func testLRCParserSkipsEmptyLines() {
        let plain = "First\n\n\nSecond\n"
        let service = LRCLibService.shared
        let lines = service.parsePlainLyrics(plain)
        XCTAssertEqual(lines.count, 2)
    }

    // MARK: - LyricsLine Timestamp Sort Ordering
    func testLyricsLineSortOrdering() {
        let lines = [
            LyricsLine(index: 2, text: "Third", timestampSeconds: 10.0),
            LyricsLine(index: 0, text: "First", timestampSeconds: 1.0),
            LyricsLine(index: 1, text: "Second", timestampSeconds: 5.0)
        ]
        let sorted = lines.sorted { $0.index < $1.index }
        XCTAssertEqual(sorted[0].text, "First")
        XCTAssertEqual(sorted[1].text, "Second")
        XCTAssertEqual(sorted[2].text, "Third")
    }

    // MARK: - Exercise Keyword Matching
    func testExerciseKeywordScoringReturnsMatch() {
        let exercise = Exercise(
            templateID: "test-exercise",
            name: "Pitch Siren",
            category: "pitch",
            exerciseDescription: "Test description",
            instruction: "Test instruction",
            focusArea: "Pitch",
            keywords: ["pitch", "siren", "range", "glide"]
        )

        let service = ExerciseRecommendationService()
        let song = Song(title: "Test Song", artist: "Test Artist")
        let transcript = "I have trouble with pitch and my range feels limited when I glide"
        let result = service.recommendExercises(
            transcript: transcript,
            song: song,
            allExercises: [exercise],
            count: 5
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Pitch Siren")
    }

    func testExerciseKeywordScoringNoMatch() {
        let exercise = Exercise(
            templateID: "test-exercise",
            name: "Breath Hiss",
            category: "breath",
            exerciseDescription: "Test",
            instruction: "Test",
            focusArea: "Breath",
            keywords: ["breath", "support", "hiss"]
        )

        let service = ExerciseRecommendationService()
        let song = Song(title: "Test Song", artist: "Test Artist")
        let transcript = "I love singing and my tone was great today"
        let result = service.recommendExercises(
            transcript: transcript,
            song: song,
            allExercises: [exercise],
            count: 5
        )

        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Karaoke Fuzzy Match Scoring
    func testKaraokeScoreHighForMatchingTitleWithKeyword() {
        let score = ExerciseRecommendationService.karaokeScore(
            candidateTitle: "Losing My Religion Karaoke",
            originalTitle: "Losing My Religion"
        )
        XCTAssertGreaterThan(score, 0.5)
    }

    func testKaraokeScoreLowForUnrelatedTitle() {
        // Score for exact match on title should exceed score for unrelated title
        let relatedScore = ExerciseRecommendationService.karaokeScore(
            candidateTitle: "Losing My Religion Karaoke",
            originalTitle: "Losing My Religion"
        )
        let unrelatedScore = ExerciseRecommendationService.karaokeScore(
            candidateTitle: "Happy Birthday Karaoke",
            originalTitle: "Losing My Religion"
        )
        XCTAssertGreaterThan(relatedScore, unrelatedScore)
    }

    func testStringSimilarityExactMatch() {
        let score = ExerciseRecommendationService.stringSimilarity("hello world", "hello world")
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testStringSimilarityNoMatch() {
        let score = ExerciseRecommendationService.stringSimilarity("abc", "xyz")
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    // MARK: - SwiftData Model Round-Trips
    func testSongModelRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Song.self, LyricsLine.self, Lesson.self, Exercise.self, configurations: config)
        let context = container.mainContext

        let song = Song(title: "Test Song", artist: "Test Artist")
        context.insert(song)
        try context.save()

        let descriptor = FetchDescriptor<Song>()
        let songs = try context.fetch(descriptor)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].title, "Test Song")
        XCTAssertEqual(songs[0].artist, "Test Artist")
    }

    func testLessonAddedToSong() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Song.self, LyricsLine.self, Lesson.self, Exercise.self, configurations: config)
        let context = container.mainContext

        let song = Song(title: "Test Song", artist: "Test Artist")
        context.insert(song)

        let lesson = Lesson(
            songID: song.id,
            audioFileURL: "file:///test.m4a",
            durationSeconds: 30.0,
            transcriptionStatus: TranscriptionStatus.done.rawValue
        )
        song.lessons.append(lesson)
        context.insert(lesson)
        try context.save()

        let descriptor = FetchDescriptor<Song>()
        let songs = try context.fetch(descriptor)
        XCTAssertEqual(songs[0].lessons.count, 1)
        XCTAssertEqual(songs[0].lessons[0].durationSeconds, 30.0, accuracy: 0.001)
    }

    func testExerciseFetchFromContext() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Song.self, LyricsLine.self, Lesson.self, Exercise.self, configurations: config)
        let context = container.mainContext

        let exercise = Exercise(
            templateID: "test-ex",
            name: "Test Exercise",
            category: "warmup",
            exerciseDescription: "A test",
            instruction: "Do the test",
            focusArea: "Testing"
        )
        context.insert(exercise)
        try context.save()

        let descriptor = FetchDescriptor<Exercise>()
        let exercises = try context.fetch(descriptor)
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].category, "warmup")
    }
}

// MARK: - Analytics Mock Tests
@MainActor
final class MockAnalyticsTracker: AnalyticsTracking {
    var events: [(name: String, params: [String: Any]?)] = []
    func logEvent(_ name: String, parameters: [String: Any]?) {
        events.append((name, parameters))
    }
}

@MainActor
final class AnalyticsTests: XCTestCase {
    func testSongAddedEventFires() {
        let mock = MockAnalyticsTracker()
        AnalyticsService.shared.tracker = mock

        AnalyticsService.shared.songAdded(source: "lrclib", hasSyncedLyrics: true)

        XCTAssertEqual(mock.events.count, 1)
        XCTAssertEqual(mock.events[0].name, "song_added")
        XCTAssertEqual(mock.events[0].params?["source"] as? String, "lrclib")
        XCTAssertEqual(mock.events[0].params?["has_synced_lyrics"] as? Bool, true)
    }

    func testLessonRecordedEventFires() {
        let mock = MockAnalyticsTracker()
        AnalyticsService.shared.tracker = mock

        AnalyticsService.shared.lessonRecorded(durationSeconds: 45.5)

        XCTAssertEqual(mock.events.count, 1)
        XCTAssertEqual(mock.events[0].name, "lesson_recorded")
        XCTAssertEqual(mock.events[0].params?["duration_seconds"] as? Double ?? 0.0, 45.5, accuracy: 0.001)
    }

    func testExercisePracticedEventFires() {
        let mock = MockAnalyticsTracker()
        AnalyticsService.shared.tracker = mock

        AnalyticsService.shared.exercisePracticed(category: "breath", templateID: "breath-hiss")

        XCTAssertEqual(mock.events.count, 1)
        XCTAssertEqual(mock.events[0].name, "exercise_practiced")
        XCTAssertEqual(mock.events[0].params?["category"] as? String, "breath")
    }
}
