// GeminiIntegrationTests.swift
// Real Firebase integration tests — skipped unless SINGCOACH_INTEGRATION=1 is set.
//
// HOW TO RUN (the test plan acts as the gate — no env var needed):
//
//   From command line:
//   xcodebuild test -scheme SingCoach \
//     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//     -testPlan SingCoach
//
//   In Xcode: Product → Test Plan → SingCoach
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
        // No skip guard — the SingCoach.xctestplan's selectedTests acts as the gate.
        // These tests only run when you explicitly use: -testPlan SingCoach
        // Regular `xcodebuild test` (no test plan) will not include them.
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

    // ⚠️ Requires a real audio file — the stub m4a below is not valid.
    // To run this properly: record a few seconds in the app, copy the .m4a path,
    // and replace `writeMinimalAudio()` with a bundle resource.
    // For now this test is skipped until a real audio fixture is added.
    func testFullPipelineWithTinyAudio() async throws {
        throw XCTSkip("Needs a real audio fixture — stub m4a is not a valid recording")
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
