// GeminiAnalysisNetworkTests.swift
// Tests the full GeminiAnalysisService.analyze() pipeline using an injected mock generator.
// This verifies the real logic path — audio file loading, single-call Pro analysis,
// response parsing, exercise matching, and all error cases — without making live HTTP calls.

import XCTest
import SwiftData
@testable import SingCoach

// MARK: - Mock Generator

/// A mock AITextGenerator that returns queued responses in order.
/// Throws if the queue is empty (guard against unexpected extra calls).
final class MockTextGenerator: AITextGenerator, @unchecked Sendable {

    private var responses: [Result<String, any Error>]
    private(set) var callCount = 0
    private(set) var lastPrompt: String?
    private(set) var lastAudioByteCount: Int?
    private(set) var lastMimeType: String?

    init(results: [Result<String, any Error>]) {
        self.responses = results
    }

    convenience init(texts: String...) {
        self.init(results: texts.map { .success($0) })
    }

    convenience init(error: any Error) {
        self.init(results: [.failure(error)])
    }

    func generateText(audioData: Data, mimeType: String, prompt: String) async throws -> String {
        lastPrompt = prompt
        lastAudioByteCount = audioData.count
        lastMimeType = mimeType
        return try dequeue()
    }

    private func dequeue() throws -> String {
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "MockTextGenerator: no response queued"])
        }
        callCount += 1
        return try responses.removeFirst().get()
    }
}

// MARK: - Fixtures

private let mockTranscript = "[0:00]\nThis is a test vocal lesson recording.\n\n[1:30]\nNow we move to the chorus section."

private let mockAnalysisJSON = """
{
  "transcript": "[0:00]\\nThis is a test vocal lesson recording.\\n\\n[1:30]\\nNow we move to the chorus section.",
  "overall": 6.5,
  "pitch": 6.5,
  "tone": 6.5,
  "breath": 7.5,
  "timing": 8.0,
  "tldr": "Tongue root tension is creating a bottleneck. Your breath support is your strongest asset.",
  "keyMoments": [
    {"timestamp": "0:18", "text": "Opening phrase sets the intonation pattern"},
    {"timestamp": "1:30", "text": "Chorus — pitch drifts on high notes"}
  ],
  "recommendedExerciseNames": ["Pitch Siren", "Lip Trill", "Breath Hiss"]
}
"""

// MARK: - Tests

@MainActor
final class GeminiAnalysisNetworkTests: XCTestCase {

    var testAudioPath: String!   // relative "Lessons/..." path passed to service
    var testAudioURL: URL!       // absolute URL for cleanup

    override func setUp() async throws {
        try await super.setUp()
        // AudioPathResolver maps "Lessons/..." relative paths to Documents/Lessons/.
        // Write the dummy file there so the service can find it.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let lessonsDir = docs.appendingPathComponent("Lessons")
        try FileManager.default.createDirectory(at: lessonsDir, withIntermediateDirectories: true)
        let filename = "test-recording-\(UUID().uuidString).m4a"
        testAudioURL = lessonsDir.appendingPathComponent(filename)
        testAudioPath = "Lessons/\(filename)"
        // Actual bytes don't matter — service reads data then passes to (mocked) generator
        try Data(repeating: 0, count: 1024).write(to: testAudioURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testAudioURL)
        try await super.tearDown()
    }

    // MARK: - Happy path

    func testAnalyzeCallsProOnce() async throws {
        let pro = MockTextGenerator(texts: mockAnalysisJSON)
        let service = GeminiAnalysisService(proGenerator: pro)

        _ = try await service.analyze(
            audioFileURL: testAudioPath,
            isPerformance: true,
            exerciseLibrary: []
        )

        XCTAssertEqual(pro.callCount, 1, "Pro should be called exactly once — single-call architecture")
        XCTAssertEqual(pro.lastAudioByteCount, 1024, "Audio bytes should be forwarded to the model")
        XCTAssertEqual(pro.lastMimeType, "audio/mp4", "m4a should map to audio/mp4 mime type")
        XCTAssertNotNil(pro.lastPrompt, "A text prompt should be sent alongside the audio")
    }

    func testAnalyzeReturnsCorrectScores() async throws {
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(texts: mockAnalysisJSON))

        let (result, transcript) = try await service.analyze(
            audioFileURL: testAudioPath,
            isPerformance: true,
            exerciseLibrary: []
        )

        XCTAssertEqual(result.overall, 6.5, accuracy: 0.01)
        XCTAssertEqual(result.pitch,   6.5, accuracy: 0.01)
        XCTAssertEqual(result.breath,  7.5, accuracy: 0.01)
        XCTAssertEqual(result.timing,  8.0, accuracy: 0.01)
        XCTAssertFalse(result.tldr.isEmpty)
        XCTAssertEqual(result.keyMoments.count, 2)
        XCTAssertEqual(result.recommendedExerciseNames.count, 3)
        XCTAssertFalse(transcript.isEmpty)
        XCTAssertTrue(transcript.contains("[0:00]"), "Transcript extracted from response should contain timestamp markers")
    }

    func testAnalyzeExtractsTranscriptFromResponse() async throws {
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(texts: mockAnalysisJSON))

        let (_, transcript) = try await service.analyze(
            audioFileURL: testAudioPath,
            isPerformance: false,
            exerciseLibrary: []
        )

        XCTAssertEqual(transcript, mockTranscript,
            "Transcript should match the `transcript` field in the Pro JSON response")
    }

    func testAnalyzeHandlesCodeFencedResponse() async throws {
        let fenced = "```json\n\(mockAnalysisJSON)\n```"
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(texts: fenced))

        let (result, _) = try await service.analyze(
            audioFileURL: testAudioPath,
            isPerformance: true,
            exerciseLibrary: []
        )

        XCTAssertEqual(result.overall, 6.5, accuracy: 0.01,
            "Should parse JSON correctly even when wrapped in markdown code fences")
    }

    func testAnalyzeProgressCallbackFires() async throws {
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(texts: mockAnalysisJSON))
        let stages = Stages()

        _ = try await service.analyze(
            audioFileURL: testAudioPath,
            isPerformance: true,
            exerciseLibrary: [],
            onProgress: { stage in stages.append(stage) }
        )

        let captured = stages.values
        XCTAssertGreaterThanOrEqual(captured.count, 3, "Should report at least loadingAudio, analyzing, matchingExercises")
        if case .loadingAudio = captured.first { /* ✅ */ } else { XCTFail("First stage should be loadingAudio") }
        XCTAssertTrue(captured.contains(.analyzing))
        XCTAssertTrue(captured.contains(.matchingExercises))
    }

    func testAnalyzeExerciseMatchingEndToEnd() async throws {
        let exercises = [
            Exercise(templateID: "ps", name: "Pitch Siren",  category: "pitch",
                     exerciseDescription: "", instruction: "", focusArea: "Pitch"),
            Exercise(templateID: "lt", name: "Lip Trill",    category: "breath",
                     exerciseDescription: "", instruction: "", focusArea: "Breath"),
            Exercise(templateID: "bh", name: "Breath Hiss",  category: "breath",
                     exerciseDescription: "", instruction: "", focusArea: "Breath"),
            Exercise(templateID: "rh", name: "Resonance Hum", category: "tone",
                     exerciseDescription: "", instruction: "", focusArea: "Tone"),
        ]
        let library = exercises.map { AIExerciseSummary(name: $0.name, category: $0.category) }
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(texts: mockAnalysisJSON))

        let (result, _) = try await service.analyze(
            audioFileURL: testAudioPath,
            isPerformance: true,
            exerciseLibrary: library
        )

        let matched = service.matchExercises(names: result.recommendedExerciseNames, from: exercises)
        XCTAssertEqual(matched.count, 3, "All 3 recommended exercises should match the library")
        let names = Set(matched.map { $0.name })
        XCTAssertTrue(names.contains("Pitch Siren"))
        XCTAssertTrue(names.contains("Lip Trill"))
        XCTAssertTrue(names.contains("Breath Hiss"))
    }

    // MARK: - Error paths

    func testThrowsAudioFileNotFound() async throws {
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(texts: mockAnalysisJSON))

        do {
            _ = try await service.analyze(
                audioFileURL: "/does/not/exist.m4a",
                isPerformance: true,
                exerciseLibrary: []
            )
            XCTFail("Should throw audioFileNotFound")
        } catch GeminiAnalysisError.audioFileNotFound {
            // ✅
        }
    }

    func testThrowsAnalysisFailedWhenProErrors() async throws {
        // Use .badURL (non-transient) so the single-retry path doesn't mask the error.
        let service = GeminiAnalysisService(proGenerator: MockTextGenerator(error: URLError(.badURL)))

        do {
            _ = try await service.analyze(
                audioFileURL: testAudioPath,
                isPerformance: true,
                exerciseLibrary: []
            )
            XCTFail("Should throw when Pro generator fails")
        } catch GeminiAnalysisError.analysisFailed {
            // ✅
        }
    }

    func testThrowsInvalidResponseWhenProReturnsNonJSON() async throws {
        let service = GeminiAnalysisService(
            proGenerator: MockTextGenerator(texts: "Sorry, I cannot analyse this recording.")
        )

        do {
            _ = try await service.analyze(
                audioFileURL: testAudioPath,
                isPerformance: true,
                exerciseLibrary: []
            )
            XCTFail("Should throw invalidResponse for non-JSON Pro output")
        } catch GeminiAnalysisError.invalidResponse {
            // ✅
        }
    }
}

// MARK: - Helpers

/// Captures stage callbacks from a background actor context for assertion on the main thread.
@MainActor
private final class Stages {
    private(set) var values: [AnalysisStage] = []
    func append(_ s: AnalysisStage) { values.append(s) }
}
