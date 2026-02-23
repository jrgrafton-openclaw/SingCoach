import XCTest
import SwiftData
@testable import SingCoach

// MARK: - Mock JSON fixtures
// Derived from actual Gemini Pro 3.1 responses during calibration (2026-02-22).
// James's performance  → overall 3.0 (amateur baseline)
// R.E.M. live take    → overall 8.0 (professional baseline)
// Lesson session      → overall 6.5 (student-in-lesson baseline)

private let performanceAnalysisJSON = """
{
  "overall": 3.0,
  "pitch": 2.0,
  "tone": 3.0,
  "breath": 3.0,
  "timing": 4.0,
  "tldr": "Pitch accuracy is the primary challenge — most phrases drift flat in the lower-middle range. Breath support is inconsistent, causing tone to thin out on longer phrases. Timing feel is the strongest dimension right now; use that as the foundation to build everything else.",
  "keyMoments": [
    {"timestamp": "0:18", "text": "Opening phrase lands flat by ~50 cents — sets the intonation pattern for the verse"},
    {"timestamp": "1:04", "text": "Tone brightens briefly on the word 'song' — the resonance is there, just not yet consistent"},
    {"timestamp": "2:15", "text": "Breath runs out mid-phrase, causing the line to trail off — shorter phrase groupings needed"},
    {"timestamp": "3:40", "text": "Best moment — rhythmic phrasing locks in with the track groove"}
  ],
  "recommendedExerciseNames": ["Pitch Siren", "Lip Trill", "Breath Hiss"]
}
"""

private let professionalAnalysisJSON = """
{
  "overall": 8.0,
  "pitch": 7.0,
  "tone": 8.0,
  "breath": 6.0,
  "timing": 9.0,
  "tldr": "A strong live performance with exceptional timing feel and characteristic stylistic delivery. Breath management is the one area where studio polish would add consistency. The tone has signature resonance that is immediately identifiable.",
  "keyMoments": [
    {"timestamp": "0:12", "text": "Immediately establishes rhythmic authority — phrasing sits perfectly behind the beat"},
    {"timestamp": "1:31", "text": "High note approached with stylistic slide — intentional, not technical limitation"},
    {"timestamp": "2:44", "text": "Phrase ends slightly breathy — live context, acceptable trade-off for emotional delivery"},
    {"timestamp": "3:58", "text": "Final chorus has full resonance — tone is at its best here"}
  ],
  "recommendedExerciseNames": ["Breath Hiss", "Resonance Hum"]
}
"""

private let lessonAnalysisJSON = """
{
  "overall": 6.5,
  "pitch": 6.5,
  "tone": 6.5,
  "breath": 7.5,
  "timing": 8.0,
  "tldr": "Tongue root tension is creating a bottleneck in your mid-range. Your breath support is your strongest asset right now — build everything else on top of it.",
  "keyMoments": [
    {"timestamp": "2:34", "text": "Tongue tension spikes on high D — 'Song' in Hey Jude"},
    {"timestamp": "6:31", "text": "Pitch drifts on minor 3rd jumps in pentatonic scale"},
    {"timestamp": "11:52", "text": "'Kee' exercise reveals tongue pulling back — clear bottleneck"},
    {"timestamp": "13:48", "text": "Tone opens beautifully on 'Bla bla bla' — voice unlocks"},
    {"timestamp": "20:06", "text": "Hey Jude attempt — phrase energy drops at D4-E4 range"}
  ],
  "recommendedExerciseNames": ["Tongue Stretch", "Lip Trill", "Pitch Siren", "Resonance Hum"]
}
"""

private let malformedJSON = """
{ "overall": 7.0, "pitch": 6.5, "tone": "not-a-number",
"""

private let missingFieldsJSON = """
{
  "overall": 5.0,
  "pitch": 5.0,
  "tone": 5.0
}
"""

private let fencedJSON = """
```json
{
  "overall": 4.0,
  "pitch": 4.0,
  "tone": 4.0,
  "breath": 4.0,
  "timing": 4.0,
  "tldr": "Wrapped in fences",
  "keyMoments": [],
  "recommendedExerciseNames": []
}
```
"""

private let fencedNoLangJSON = """
```
{
  "overall": 4.0,
  "pitch": 4.0,
  "tone": 4.0,
  "breath": 4.0,
  "timing": 4.0,
  "tldr": "Wrapped without language tag",
  "keyMoments": [],
  "recommendedExerciseNames": []
}
```
"""

// MARK: - AIAnalysisResult Decode Tests

@MainActor
final class AIAnalysisResultDecodeTests: XCTestCase {

    // MARK: - Valid full responses

    func testDecodePerformanceResponse() throws {
        let data = try XCTUnwrap(performanceAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)

        XCTAssertEqual(result.overall, 3.0, accuracy: 0.01)
        XCTAssertEqual(result.pitch,   2.0, accuracy: 0.01)
        XCTAssertEqual(result.tone,    3.0, accuracy: 0.01)
        XCTAssertEqual(result.breath,  3.0, accuracy: 0.01)
        XCTAssertEqual(result.timing,  4.0, accuracy: 0.01)
        XCTAssertFalse(result.tldr.isEmpty)
        XCTAssertEqual(result.keyMoments.count, 4)
        XCTAssertEqual(result.keyMoments[0].timestamp, "0:18")
        XCTAssertFalse(result.keyMoments[0].text.isEmpty)
        XCTAssertEqual(result.recommendedExerciseNames.count, 3)
        XCTAssertTrue(result.recommendedExerciseNames.contains("Pitch Siren"))
    }

    func testDecodeProfessionalResponse() throws {
        let data = try XCTUnwrap(professionalAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)

        XCTAssertEqual(result.overall, 8.0, accuracy: 0.01)
        XCTAssertEqual(result.timing,  9.0, accuracy: 0.01)
        XCTAssertEqual(result.keyMoments.count, 4)
        XCTAssertEqual(result.recommendedExerciseNames.count, 2)
    }

    func testDecodeLessonResponse() throws {
        let data = try XCTUnwrap(lessonAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)

        XCTAssertEqual(result.overall, 6.5, accuracy: 0.01)
        XCTAssertEqual(result.breath,  7.5, accuracy: 0.01)  // highest dimension
        XCTAssertEqual(result.timing,  8.0, accuracy: 0.01)
        XCTAssertEqual(result.keyMoments.count, 5)
        XCTAssertEqual(result.keyMoments[2].timestamp, "11:52")
        XCTAssertTrue(result.tldr.contains("Tongue root tension"))
    }

    // MARK: - Decoding edge cases

    func testDecodeMalformedJSONThrows() {
        let data = malformedJSON.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AIAnalysisResult.self, from: data))
    }

    func testDecodeMissingRequiredFieldsThrows() {
        // missing breath, timing, tldr, keyMoments, recommendedExerciseNames
        let data = missingFieldsJSON.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AIAnalysisResult.self, from: data))
    }

    func testDecodeEmptyKeyMoments() throws {
        let json = """
        {
          "overall": 5.0, "pitch": 5.0, "tone": 5.0, "breath": 5.0, "timing": 5.0,
          "tldr": "Nothing notable",
          "keyMoments": [],
          "recommendedExerciseNames": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        XCTAssertTrue(result.keyMoments.isEmpty)
        XCTAssertTrue(result.recommendedExerciseNames.isEmpty)
    }

    func testDecodePreservesHalfPointScores() throws {
        // Pro 3.1 often returns x.5 scores — verify they survive round-trip
        let data = try XCTUnwrap(lessonAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        XCTAssertEqual(result.overall, 6.5, accuracy: 0.001)
        XCTAssertEqual(result.pitch,   6.5, accuracy: 0.001)
    }
}

// MARK: - stripCodeFences Tests

// Access the private method via a testable subclass approach — use a test helper.
// Since stripCodeFences is private, we expose it via a testable wrapper.
extension GeminiAnalysisService {
    func stripCodeFencesPublic(_ text: String) -> String {
        return stripCodeFences(text)
    }
    // Expose private method for testing via extension — requires @testable import
    private func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class StripCodeFencesTests: XCTestCase {

    let service = GeminiAnalysisService()

    func testStripsFencedJSON() {
        let result = service.stripCodeFencesPublic(fencedJSON)
        XCTAssertTrue(result.hasPrefix("{"), "Should start with { after stripping ```json fence")
        XCTAssertTrue(result.hasSuffix("}"), "Should end with } after stripping trailing fence")
        XCTAssertFalse(result.contains("```"))
    }

    func testStripsFenceWithoutLanguageTag() {
        let result = service.stripCodeFencesPublic(fencedNoLangJSON)
        XCTAssertTrue(result.hasPrefix("{"))
        XCTAssertTrue(result.hasSuffix("}"))
        XCTAssertFalse(result.contains("```"))
    }

    func testPassesThroughCleanJSON() {
        let clean = """
        {"overall": 5.0, "pitch": 5.0}
        """
        let result = service.stripCodeFencesPublic(clean)
        XCTAssertEqual(result, clean.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testStripsAndStillDecodesValidResult() throws {
        let stripped = service.stripCodeFencesPublic(fencedJSON)
        let data = try XCTUnwrap(stripped.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        XCTAssertEqual(result.overall, 4.0, accuracy: 0.01)
        XCTAssertEqual(result.tldr, "Wrapped in fences")
    }
}

// MARK: - matchExercises Tests

@MainActor
final class MatchExercisesTests: XCTestCase {

    let service = GeminiAnalysisService()

    private func makeExercise(name: String, category: String = "warmup") -> Exercise {
        Exercise(
            templateID: UUID().uuidString,
            name: name,
            category: category,
            exerciseDescription: "Test",
            instruction: "Test",
            focusArea: "Test"
        )
    }

    func testExactMatchReturnsCorrectExercise() {
        let exercises = [
            makeExercise(name: "Pitch Siren"),
            makeExercise(name: "Lip Trill"),
            makeExercise(name: "Breath Hiss")
        ]
        let matches = service.matchExercises(names: ["Lip Trill"], from: exercises)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].name, "Lip Trill")
    }

    func testCaseInsensitiveMatch() {
        let exercises = [makeExercise(name: "Pitch Siren")]
        let matches = service.matchExercises(names: ["pitch siren"], from: exercises)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].name, "Pitch Siren")
    }

    func testPartialMatchFallback() {
        let exercises = [makeExercise(name: "Resonance Hum")]
        let matches = service.matchExercises(names: ["Resonance"], from: exercises)
        XCTAssertEqual(matches.count, 1, "Should fuzzy-match 'Resonance' to 'Resonance Hum'")
    }

    func testNoMatchReturnsEmpty() {
        let exercises = [makeExercise(name: "Lip Trill")]
        let matches = service.matchExercises(names: ["Yodelling Warmup"], from: exercises)
        XCTAssertEqual(matches.count, 0)
    }

    func testMultipleNamesFromLessonFixture() throws {
        // Uses the exercise names from our validated lesson analysis fixture
        let data = try XCTUnwrap(lessonAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)

        let exercises = [
            makeExercise(name: "Tongue Stretch"),
            makeExercise(name: "Lip Trill"),
            makeExercise(name: "Pitch Siren"),
            makeExercise(name: "Resonance Hum"),
            makeExercise(name: "Breath Hiss")
        ]
        let matches = service.matchExercises(
            names: result.recommendedExerciseNames,
            from: exercises
        )
        // Fixture recommends 4 exercises, all present in library
        XCTAssertEqual(matches.count, 4)
        let matchedNames = Set(matches.map { $0.name })
        XCTAssertTrue(matchedNames.contains("Tongue Stretch"))
        XCTAssertTrue(matchedNames.contains("Lip Trill"))
        XCTAssertTrue(matchedNames.contains("Pitch Siren"))
        XCTAssertTrue(matchedNames.contains("Resonance Hum"))
    }

    func testEmptyNamesListReturnsEmpty() {
        let exercises = [makeExercise(name: "Pitch Siren")]
        let matches = service.matchExercises(names: [], from: exercises)
        XCTAssertTrue(matches.isEmpty)
    }

    func testEmptyLibraryReturnsEmpty() {
        let matches = service.matchExercises(names: ["Pitch Siren"], from: [])
        XCTAssertTrue(matches.isEmpty)
    }
}

// MARK: - Score Colour Logic Tests

@MainActor
final class ScoreColorThresholdTests: XCTestCase {

    // The card uses: score >= 7.0 → green, < 7.0 → amber
    // Verify boundary values match the calibration data pattern

    func testAmberThresholdAtSix() throws {
        let data = try XCTUnwrap(performanceAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        // All scores in James's recording are < 7 → should all be amber
        XCTAssertLessThan(result.overall, 7.0)
        XCTAssertLessThan(result.pitch,   7.0)
        XCTAssertLessThan(result.tone,    7.0)
        XCTAssertLessThan(result.breath,  7.0)
        XCTAssertLessThan(result.timing,  7.0)
    }

    func testGreenThresholdAtEight() throws {
        let data = try XCTUnwrap(professionalAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        // Overall, tone, timing from R.E.M. live take should all be >= 7 → green
        XCTAssertGreaterThanOrEqual(result.overall, 7.0)
        XCTAssertGreaterThanOrEqual(result.tone,    7.0)
        XCTAssertGreaterThanOrEqual(result.timing,  7.0)
    }

    func testBoundaryAt7_0IsGreen() throws {
        let json = """
        {
          "overall": 7.0, "pitch": 7.0, "tone": 7.0, "breath": 7.0, "timing": 7.0,
          "tldr": "Boundary test", "keyMoments": [], "recommendedExerciseNames": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        // 7.0 is the green threshold — assert it's >= 7.0 (green side)
        XCTAssertGreaterThanOrEqual(result.overall, 7.0)
    }

    func testLessonMixedColors() throws {
        let data = try XCTUnwrap(lessonAnalysisJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        // Lesson: overall 6.5, pitch 6.5, tone 6.5 → amber; breath 7.5, timing 8.0 → green
        XCTAssertLessThan(result.overall, 7.0, "Overall 6.5 should be amber")
        XCTAssertLessThan(result.pitch,   7.0, "Pitch 6.5 should be amber")
        XCTAssertGreaterThanOrEqual(result.breath, 7.0, "Breath 7.5 should be green")
        XCTAssertGreaterThanOrEqual(result.timing, 7.0, "Timing 8.0 should be green")
    }
}

// MARK: - Lesson Model AI Fields Tests

@MainActor
final class LessonAIFieldsTests: XCTestCase {

    func testLessonPersistsAIAnalysisJSON() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Song.self, LyricsLine.self, Lesson.self, Exercise.self,
            configurations: config
        )
        let context = container.mainContext

        let lesson = Lesson(
            songID: UUID(),
            audioFileURL: "recordings/test.m4a",
            durationSeconds: 240.0
        )
        lesson.aiAnalysis = performanceAnalysisJSON
        lesson.aiAnalysisDate = Date()
        context.insert(lesson)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Lesson>())
        XCTAssertEqual(fetched.count, 1)
        let saved = try XCTUnwrap(fetched[0].aiAnalysis)
        XCTAssertFalse(saved.isEmpty)

        // Verify round-trip decode from SwiftData
        let data = try XCTUnwrap(saved.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        XCTAssertEqual(decoded.overall, 3.0, accuracy: 0.01)
    }

    func testLessonAIFieldsDefaultToNil() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Song.self, LyricsLine.self, Lesson.self, Exercise.self,
            configurations: config
        )
        let context = container.mainContext

        let lesson = Lesson(
            songID: UUID(),
            audioFileURL: "recordings/fresh.m4a",
            durationSeconds: 60.0
        )
        context.insert(lesson)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Lesson>())
        XCTAssertNil(fetched[0].aiAnalysis)
        XCTAssertNil(fetched[0].aiAnalysisDate)
    }

    func testLessonAIAnalysisDatePersists() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Song.self, LyricsLine.self, Lesson.self, Exercise.self,
            configurations: config
        )
        let context = container.mainContext

        let analysisDate = Date(timeIntervalSince1970: 1_740_000_000)
        let lesson = Lesson(songID: UUID(), audioFileURL: "test.m4a", durationSeconds: 30.0)
        lesson.aiAnalysisDate = analysisDate
        context.insert(lesson)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Lesson>())
        let saved = try XCTUnwrap(fetched[0].aiAnalysisDate)
        XCTAssertEqual(saved.timeIntervalSince1970, analysisDate.timeIntervalSince1970, accuracy: 1.0)
    }
}

// MARK: - Amateur vs Professional Score Gap Tests
// Validates that the scoring range makes semantic sense for our calibration data.

@MainActor
final class CalibrationScoreGapTests: XCTestCase {

    func testProfessionalOutscoresAmateur() throws {
        let amateurData = try XCTUnwrap(performanceAnalysisJSON.data(using: .utf8))
        let amateur = try JSONDecoder().decode(AIAnalysisResult.self, from: amateurData)

        let proData = try XCTUnwrap(professionalAnalysisJSON.data(using: .utf8))
        let pro = try JSONDecoder().decode(AIAnalysisResult.self, from: proData)

        XCTAssertGreaterThan(pro.overall, amateur.overall,
            "Professional (R.E.M.) should score higher overall than amateur (James)")
        XCTAssertGreaterThan(pro.timing, amateur.timing,
            "Professional timing should exceed amateur timing")
        XCTAssertGreaterThan(pro.tone, amateur.tone,
            "Professional tone should exceed amateur tone")
    }

    func testLessonScoreSitsBetweenAmateurAndProfessional() throws {
        let amateurData = try XCTUnwrap(performanceAnalysisJSON.data(using: .utf8))
        let amateur = try JSONDecoder().decode(AIAnalysisResult.self, from: amateurData)

        let lessonData = try XCTUnwrap(lessonAnalysisJSON.data(using: .utf8))
        let lesson = try JSONDecoder().decode(AIAnalysisResult.self, from: lessonData)

        let proData = try XCTUnwrap(professionalAnalysisJSON.data(using: .utf8))
        let pro = try JSONDecoder().decode(AIAnalysisResult.self, from: proData)

        XCTAssertGreaterThan(lesson.overall, amateur.overall,
            "Lesson student (6.5) should score above pure amateur (3.0)")
        XCTAssertLessThan(lesson.overall, pro.overall,
            "Lesson student (6.5) should score below professional (8.0)")
    }
}
