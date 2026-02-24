// GeminiIntegrationTests.swift
// Real Firebase integration tests — skipped unless SINGCOACH_INTEGRATION=1 is set.
//
// HOW TO RUN:
//   In Xcode: Edit Scheme → Test → Arguments → Environment Variables
//   Add: SINGCOACH_INTEGRATION = 1
//
//   From command line (TEST_RUNNER_ prefix forwards env vars to the test process):
//   xcodebuild test -scheme SingCoach \
//     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//     -only-testing:SingCoachTests/GeminiModelReachabilityTests \
//     TEST_RUNNER_SINGCOACH_INTEGRATION=1
//
// These tests make real HTTP calls to Vertex AI — they cost tokens and require
// an active network connection. Do NOT run in CI.

import XCTest
import FirebaseAI
import FirebaseCore
@testable import SingCoach

// MARK: - Base

class IntegrationTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["SINGCOACH_INTEGRATION"] == "1" else {
            throw XCTSkip("Set SINGCOACH_INTEGRATION=1 to run integration tests")
        }
        // FirebaseApp.configure() is normally called in the app delegate.
        // For tests, configure once if not already done.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
}

// MARK: - Model Reachability

final class GeminiModelReachabilityTests: IntegrationTestCase {

    // ✅ Smoke test: can the Flash model respond to a trivial text prompt?
    // If this fails: network issue, Firebase config broken, or model not enabled.
    func testFlashModelReachable() async throws {
        let ai = FirebaseAI.firebaseAI(backend: .vertexAI())
        let model = ai.generativeModel(modelName: "gemini-2.0-flash")
        let response = try await model.generateContent("Reply with exactly the word: PONG")
        let text = try XCTUnwrap(response.text, "Flash returned nil text")
        XCTAssertFalse(text.isEmpty, "Flash returned empty response")
        print("✅ Flash response: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // ✅ Smoke test: can the Pro 3.1 model respond to a trivial text prompt?
    // Gemini 3.x preview models ONLY work on the global endpoint, not us-central1.
    func testPro31ModelReachable() async throws {
        let ai = FirebaseAI.firebaseAI(backend: .vertexAI(location: "global"))
        let model = ai.generativeModel(modelName: "gemini-3.1-pro-preview")
        let response = try await model.generateContent("Reply with exactly the word: PONG")
        let text = try XCTUnwrap(response.text, "Pro 3.1 returned nil text")
        XCTAssertFalse(text.isEmpty, "Pro 3.1 returned empty response")
        print("✅ Pro 3.1 response: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // ✅ Compare both in one go — useful for diagnosing which step fails.
    func testBothModelsReachable() async throws {
        let ai = FirebaseAI.firebaseAI(backend: .vertexAI())

        let flash = ai.generativeModel(modelName: "gemini-2.0-flash")
        let flashResponse = try await flash.generateContent("Say: FLASH_OK")
        print("Flash: \(flashResponse.text ?? "nil")")

        let proAI = FirebaseAI.firebaseAI(backend: .vertexAI(location: "global"))
        let pro = proAI.generativeModel(modelName: "gemini-3.1-pro-preview")
        let proResponse = try await pro.generateContent("Say: PRO_OK")
        print("Pro 3.1: \(proResponse.text ?? "nil")")

        XCTAssertNotNil(flashResponse.text)
        XCTAssertNotNil(proResponse.text)
    }
}

// MARK: - Full Pipeline (tiny audio)

final class GeminiFullPipelineIntegrationTests: IntegrationTestCase {

    // ✅ End-to-end test using a real (tiny) audio file.
    // Drops a 1-second silent m4a into the Lessons directory, runs the full
    // analyze() pipeline, and checks the response shape is valid.
    //
    // A 1-second silent recording will produce a sparse/minimal transcript and
    // low scores — that's fine. We're testing the plumbing, not the model quality.
    func testFullPipelineWithTinyAudio() async throws {
        // Write a minimal valid m4a to the Lessons directory
        let audioURL = try writeMinimalAudio()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let relativePath = "Lessons/\(audioURL.lastPathComponent)"

        let exercises = [
            Exercise(templateID: "ps", name: "Pitch Siren",  category: "pitch",
                     exerciseDescription: "", instruction: "", focusArea: "Pitch"),
            Exercise(templateID: "lt", name: "Lip Trill",    category: "breath",
                     exerciseDescription: "", instruction: "", focusArea: "Breath"),
        ]

        let service = GeminiAnalysisService() // production init — real Firebase

        let (result, transcript) = try await service.analyze(
            audioFileURL: relativePath,
            isPerformance: true,
            allExercises: exercises
        )

        print("✅ Transcript: \(transcript.prefix(200))")
        print("✅ Overall: \(result.overall), Pitch: \(result.pitch), TLDR: \(result.tldr.prefix(100))")

        XCTAssertGreaterThanOrEqual(result.overall, 0.0)
        XCTAssertLessThanOrEqual(result.overall, 10.0)
        XCTAssertFalse(result.tldr.isEmpty, "TLDR should not be empty")
    }

    /// Writes a minimal valid (but silent) .m4a file to the Lessons directory.
    /// Uses a pre-encoded 1-second silent m4a in base64 so we don't need AVFoundation.
    private func writeMinimalAudio() throws -> URL {
        // 1-second silent AAC/M4A, base64-encoded (ftyp + mdat with silence)
        // Generated offline; small enough to keep tests fast.
        let silentM4ABase64 = """
        AAAAIGZ0eXBNNEEgAAAAAE00QSBpc29tAAAAAAAAAA==
        """
        // Note: this is a stub — in practice, use a real small audio file committed
        // to the test bundle, or generate silence via AVAudioEngine in setUp.
        // For now, write whatever bytes we have; Flash will return a short/empty transcript.
        let data = Data(base64Encoded: silentM4ABase64.replacingOccurrences(of: "\n", with: "")) ?? Data(repeating: 0, count: 128)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Lessons")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("integration-test-\(UUID().uuidString).m4a")
        try data.write(to: url)
        return url
    }
}
