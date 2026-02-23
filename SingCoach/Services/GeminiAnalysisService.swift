import Foundation
import FirebaseAI

// MARK: - Result Types

struct AIKeyMoment: Codable {
    var timestamp: String
    var text: String
}

struct AIAnalysisResult: Codable {
    var overall: Double
    var pitch: Double
    var tone: Double
    var breath: Double
    var timing: Double
    var tldr: String
    var keyMoments: [AIKeyMoment]
    var recommendedExerciseNames: [String]
}

// MARK: - Errors

enum GeminiAnalysisError: LocalizedError {
    case audioFileNotFound
    case audioFileTooLarge(sizeMB: Double)
    case transcriptionFailed(String)
    case analysisFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound:
            return "Audio file not found"
        case .audioFileTooLarge(let mb):
            return "Audio file is \(String(format: "%.0f", mb))MB — exceeds the 19MB analysis limit"
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        case .analysisFailed(let msg):
            return "Analysis failed: \(msg)"
        case .invalidResponse(let msg):
            return "Could not read AI response: \(msg)"
        }
    }
}

// MARK: - Service

final class GeminiAnalysisService {

    private let ai = FirebaseAI.firebaseAI(backend: .vertexAI())
    private let maxFileSizeBytes = 19 * 1024 * 1024 // 19 MB safety margin

    // MARK: - Public API

    /// Full pipeline: transcription via Flash → analysis + recommendations via Pro 3.1.
    /// Accepts primitives (no SwiftData models) so it is safe to call across actor boundaries.
    func analyze(
        audioFileURL: String,
        isPerformance: Bool,
        allExercises: [Exercise]
    ) async throws -> (result: AIAnalysisResult, transcript: String) {

        let audioURL = AudioPathResolver.resolvedURL(audioFileURL)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw GeminiAnalysisError.audioFileNotFound
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        if fileSize > maxFileSizeBytes {
            throw GeminiAnalysisError.audioFileTooLarge(sizeMB: Double(fileSize) / 1_048_576)
        }

        let audioData = try Data(contentsOf: audioURL)
        let mimeType: String
        switch audioURL.pathExtension.lowercased() {
        case "mp3":  mimeType = "audio/mpeg"
        case "wav":  mimeType = "audio/wav"
        case "aac":  mimeType = "audio/aac"
        default:     mimeType = "audio/mp4"  // m4a, mp4
        }

        // Step 1 — Transcription (cheap Flash model)
        let transcript = try await transcribe(audioData: audioData, mimeType: mimeType)

        // Step 2 — Analysis + recommendations (Pro 3.1)
        let result = try await analyzeTranscript(
            transcript: transcript,
            isPerformance: isPerformance,
            allExercises: allExercises
        )

        return (result, transcript)
    }

    // MARK: - Match recommended names to Exercise objects

    func matchExercises(names: [String], from allExercises: [Exercise]) -> [Exercise] {
        names.compactMap { name in
            let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
            // Exact match first, then contains
            return allExercises.first { $0.name.lowercased() == lower }
                ?? allExercises.first {
                    $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased())
                }
        }
    }

    // MARK: - Step 1: Transcription

    private func transcribe(audioData: Data, mimeType: String) async throws -> String {
        let model = ai.generativeModel(
            modelName: "gemini-2.0-flash",
            systemInstruction: ModelContent(role: "system", parts: transcriptionSystemPrompt)
        )

        let audioPart = InlineDataPart(data: audioData, mimeType: mimeType)

        let response: GenerateContentResponse
        do {
            response = try await model.generateContent(audioPart)
        } catch {
            throw GeminiAnalysisError.transcriptionFailed(error.localizedDescription)
        }

        guard let text = response.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiAnalysisError.transcriptionFailed("Model returned empty transcript")
        }

        return text
    }

    // MARK: - Step 2: Analysis

    private func analyzeTranscript(
        transcript: String,
        isPerformance: Bool,
        allExercises: [Exercise]
    ) async throws -> AIAnalysisResult {

        let model = ai.generativeModel(
            modelName: "gemini-3.1-pro-preview",
            systemInstruction: ModelContent(
                role: "system",
                parts: isPerformance ? performanceSystemPrompt : lessonSystemPrompt
            )
        )

        let exerciseList = allExercises.isEmpty
            ? "(no exercises in library yet)"
            : allExercises.map { "- \($0.name) [\($0.category)]" }.joined(separator: "\n")

        let userPrompt = """
        TRANSCRIPT:
        \(transcript)

        ---

        AVAILABLE EXERCISES (use EXACT names when recommending):
        \(exerciseList)

        ---

        Respond with ONLY the JSON object. No markdown fences, no explanation.
        """

        let response: GenerateContentResponse
        do {
            response = try await model.generateContent(userPrompt)
        } catch {
            throw GeminiAnalysisError.analysisFailed(error.localizedDescription)
        }

        guard let text = response.text else {
            throw GeminiAnalysisError.analysisFailed("Model returned empty response")
        }

        let cleaned = stripCodeFences(text)

        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiAnalysisError.invalidResponse("Could not encode response as UTF-8")
        }

        do {
            return try JSONDecoder().decode(AIAnalysisResult.self, from: data)
        } catch {
            throw GeminiAnalysisError.invalidResponse(String(cleaned.prefix(300)))
        }
    }

    // MARK: - Prompts

    private var transcriptionSystemPrompt: String {
        """
        You are an expert audio transcriptionist. Transcribe the audio recording as accurately as possible.
        Insert a timestamp marker in the format [M:SS] at the start of each new paragraph or whenever \
        the speaker, topic, or scene changes significantly.
        Output ONLY the transcript text with embedded timestamp markers. No commentary, headers, or extra text.
        """
    }

    private var performanceSystemPrompt: String {
        """
        You are an expert vocal coach evaluating a student's solo singing performance.
        You will receive a timestamped transcript of the recording.

        Evaluate these five dimensions on a 0.0–10.0 scale:
        • pitch (intonation accuracy, staying on note, interval accuracy)
        • tone (resonance, warmth, consistency of vocal colour)
        • breath (support, phrase length, control, tension signs)
        • timing (rhythm, feel, phrasing groove)
        • overall (holistic impression — weighted by pitch and tone)

        Scoring guide:
          8–10 Professional or near-professional quality
          6–7  Developing singer with solid technique emerging
          4–5  Amateur with clear fundamentals but significant rough edges
          1–3  Foundational technical issues across multiple areas

        Respond ONLY with a JSON object matching this exact schema (no markdown, no extra keys):
        {
          "overall": <number 0.0–10.0>,
          "pitch": <number 0.0–10.0>,
          "tone": <number 0.0–10.0>,
          "breath": <number 0.0–10.0>,
          "timing": <number 0.0–10.0>,
          "tldr": "<2–3 sentences: biggest strength, clearest area to work on, and the single most impactful drill>",
          "keyMoments": [
            {"timestamp": "<M:SS>", "text": "<what happened and its vocal significance>"}
          ],
          "recommendedExerciseNames": ["<exact name from list>", ...]
        }

        keyMoments: include 3–5 moments (both positives and issues). Reference timestamps from the transcript.
        recommendedExerciseNames: recommend 3–5 exercises by EXACT name from the list provided.
        """
    }

    private var lessonSystemPrompt: String {
        """
        You are an expert vocal coach analysing a student's singing lesson from a transcript.
        The transcript contains both teacher instruction and student singing. \
        Base ALL scores ONLY on the student's actual singing — exclude teacher demonstrations.

        Evaluate these five dimensions on a 0.0–10.0 scale:
        • pitch (intonation accuracy in exercises and song attempts)
        • tone (resonance and quality when student sings)
        • breath (support and control during student's singing)
        • timing (rhythm and feel in student's singing)
        • overall (holistic impression of student's current level)

        Scoring guide (student's singing only):
          8–10 Strong technique emerging clearly, taking coaching well
          6–7  Showing improvement and responding to exercises
          4–5  Early stage, fundamentals present but inconsistent
          1–3  Foundational issues across multiple dimensions

        Respond ONLY with a JSON object matching this exact schema (no markdown, no extra keys):
        {
          "overall": <number 0.0–10.0>,
          "pitch": <number 0.0–10.0>,
          "tone": <number 0.0–10.0>,
          "breath": <number 0.0–10.0>,
          "timing": <number 0.0–10.0>,
          "tldr": "<2–3 sentences: the root cause issue the lesson revealed, what showed progress, and the #1 drill to practise before the next lesson>",
          "keyMoments": [
            {"timestamp": "<M:SS>", "text": "<what happened — exercise, breakthrough, or persistent issue — and its significance>"}
          ],
          "recommendedExerciseNames": ["<exact name from list>", ...]
        }

        keyMoments: include 4–6 moments covering both the exercises covered and notable student moments.
        recommendedExerciseNames: recommend 3–5 exercises by EXACT name from the list provided, \
        prioritising what the lesson content revealed the student needs most.
        """
    }

    // MARK: - Utilities

    private func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
