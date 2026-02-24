import Foundation
import FirebaseAI

// MARK: - Text Generator Protocol
// Abstracts the Firebase generateContent call so tests can inject a mock
// without needing access to Firebase SDK internals.

protocol AITextGenerator: Sendable {
    /// Sends audio bytes + mime type to the model, returns the text response.
    func generateText(audioData: Data, mimeType: String) async throws -> String
    /// Sends a text-only prompt, returns the model's text response.
    func generateText(prompt: String) async throws -> String
}

// Production implementation backed by a real Firebase GenerativeModel
struct FirebaseTextGenerator: AITextGenerator {
    let model: GenerativeModel

    func generateText(audioData: Data, mimeType: String) async throws -> String {
        let audioPart = InlineDataPart(data: audioData, mimeType: mimeType)
        let response = try await model.generateContent(audioPart)
        guard let text = response.text else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    func generateText(prompt: String) async throws -> String {
        let response = try await model.generateContent(prompt)
        guard let text = response.text else {
            throw URLError(.badServerResponse)
        }
        return text
    }
}

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

    private let maxFileSizeBytes = 19 * 1024 * 1024 // 19 MB safety margin

    // Overrideable for testing; nil = use real Firebase models
    private let flashGenerator: AITextGenerator?
    private let proGenerator: AITextGenerator?

    /// Production init — uses real Firebase Vertex AI models.
    init() {
        self.flashGenerator = nil
        self.proGenerator = nil
    }

    /// Test init — inject mock generators to avoid real Firebase HTTP calls.
    init(flashGenerator: any AITextGenerator, proGenerator: any AITextGenerator) {
        self.flashGenerator = flashGenerator
        self.proGenerator = proGenerator
    }

    private func makeFlashGenerator() -> any AITextGenerator {
        if let g = flashGenerator { return g }
        let ai = FirebaseAI.firebaseAI(backend: .vertexAI())
        return FirebaseTextGenerator(model: ai.generativeModel(
            modelName: "gemini-2.0-flash",
            systemInstruction: ModelContent(role: "system", parts: transcriptionSystemPrompt)
        ))
    }

    /// Builds a `GenerativeModel` whose response is constrained to valid JSON matching the
    /// `AIAnalysisResult` schema, with `recommendedExerciseNames` locked to the provided list.
    private func makeProGenerator(isPerformance: Bool, exerciseNames: [String]) -> any AITextGenerator {
        if let g = proGenerator { return g }
        // Gemini 3.x preview models are only available on the global endpoint,
        // not us-central1. Must pass location: "global" explicitly.
        let ai = FirebaseAI.firebaseAI(backend: .vertexAI(location: "global"))
        let schema = buildResponseSchema(exerciseNames: exerciseNames)
        let config = GenerationConfig(
            responseMIMEType: "application/json",
            responseSchema: schema
        )
        return FirebaseTextGenerator(model: ai.generativeModel(
            modelName: "gemini-3.1-pro-preview",
            generationConfig: config,
            systemInstruction: ModelContent(
                role: "system",
                parts: isPerformance ? performanceSystemPrompt : lessonSystemPrompt
            )
        ))
    }

    /// Builds the JSON response schema for `AIAnalysisResult`.
    /// `recommendedExerciseNames` is constrained to an enum of exact exercise names
    /// so the model cannot hallucinate or paraphrase exercise names.
    private func buildResponseSchema(exerciseNames: [String]) -> Schema {
        let nameSchema: Schema = exerciseNames.isEmpty
            ? .string()
            : .enumeration(values: exerciseNames,
                           description: "Exact exercise name from the provided list")

        return Schema.object(
            properties: [
                "overall":   .double(description: "0.0–10.0 holistic score"),
                "pitch":     .double(description: "0.0–10.0 intonation score"),
                "tone":      .double(description: "0.0–10.0 resonance / vocal colour score"),
                "breath":    .double(description: "0.0–10.0 breath support score"),
                "timing":    .double(description: "0.0–10.0 rhythm and feel score"),
                "tldr":      .string(description: "2–3 sentence summary of the performance"),
                "keyMoments": .array(
                    items: .object(
                        properties: [
                            "timestamp": .string(description: "M:SS format"),
                            "text":      .string(description: "What happened and its vocal significance")
                        ]
                    ),
                    description: "3–5 notable moments from the recording"
                ),
                "recommendedExerciseNames": .array(
                    items: nameSchema,
                    description: "4–6 exercises chosen from the provided list, covering multiple weak dimensions",
                    minItems: 4,
                    maxItems: 6
                )
            ]
        )
    }

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

    /// Basic name-based match (exact → contains → word overlap).
    func matchExercises(names: [String], from allExercises: [Exercise]) -> [Exercise] {
        var usedIDs = Set<UUID>()
        return names.compactMap { name in
            let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
            let match = allExercises.first { $0.name.lowercased() == lower && !usedIDs.contains($0.id) }
                ?? allExercises.first {
                    !usedIDs.contains($0.id) &&
                    ($0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased()))
                }
                ?? bestWordOverlapMatch(query: lower, candidates: allExercises, excluding: usedIDs)
            if let m = match { usedIDs.insert(m.id) }
            return match
        }
    }

    /// Smart match + supplement: matches LLM names then fills to `minimum` using
    /// weakest-scoring vocal dimensions → category mapping.
    func matchAndSupplement(
        names: [String],
        result: AIAnalysisResult,
        allExercises: [Exercise],
        minimum: Int = 4,
        maximum: Int = 6
    ) -> [Exercise] {
        var exercises = matchExercises(names: names, from: allExercises)
        guard exercises.count < minimum else {
            return Array(exercises.prefix(maximum))
        }

        var usedIDs = Set(exercises.map(\.id))

        // Map each vocal dimension score to the category that trains it.
        // Lower score = higher need. Sort ascending so we fill weakest first.
        let dimToCategories: [(score: Double, categories: [String])] = [
            (result.breath,  ["breath"]),
            (result.pitch,   ["pitch"]),
            (result.tone,    ["resonance", "register"]),
            (result.timing,  ["agility"]),
            // warmup always helpful as a filler
            (5.0,            ["warmup"]),
            (6.0,            ["vowel"]),
        ].sorted { $0.score < $1.score }

        for dim in dimToCategories {
            if exercises.count >= minimum { break }
            for cat in dim.categories {
                if exercises.count >= minimum { break }
                if let ex = allExercises.first(where: { $0.category == cat && !usedIDs.contains($0.id) }) {
                    exercises.append(ex)
                    usedIDs.insert(ex.id)
                }
            }
        }

        return Array(exercises.prefix(maximum))
    }

    // MARK: - Word overlap matching helper

    /// Returns the candidate whose name shares the most words with `query` (threshold ≥ 0.4).
    private func bestWordOverlapMatch(
        query: String,
        candidates: [Exercise],
        excluding: Set<UUID>
    ) -> Exercise? {
        let queryWords = Set(
            query.components(separatedBy: CharacterSet.alphanumerics.inverted)
                 .filter { $0.count > 2 }
        )
        guard !queryWords.isEmpty else { return nil }

        var best: (exercise: Exercise, score: Double)? = nil
        for candidate in candidates where !excluding.contains(candidate.id) {
            let candWords = Set(
                candidate.name.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 2 }
            )
            let overlap = Double(queryWords.intersection(candWords).count)
            let score = overlap / Double(max(queryWords.count, candWords.count))
            if score >= 0.4 && (best == nil || score > best!.score) {
                best = (candidate, score)
            }
        }
        return best?.exercise
    }

    // MARK: - Step 1: Transcription

    private func transcribe(audioData: Data, mimeType: String) async throws -> String {
        let generator = makeFlashGenerator()

        do {
            let text = try await generator.generateText(audioData: audioData, mimeType: mimeType)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiAnalysisError.transcriptionFailed("Model returned empty transcript")
            }
            return text
        } catch let e as GeminiAnalysisError {
            throw e
        } catch {
            throw GeminiAnalysisError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Step 2: Analysis

    private func analyzeTranscript(
        transcript: String,
        isPerformance: Bool,
        allExercises: [Exercise]
    ) async throws -> AIAnalysisResult {

        let exerciseNames = allExercises.map(\.name)
        // Model is created with a response schema that constrains recommendedExerciseNames
        // to exactly the exercise names in the library — no fuzzy matching needed.
        let generator = makeProGenerator(isPerformance: isPerformance, exerciseNames: exerciseNames)

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

        let raw: String
        do {
            raw = try await generator.generateText(prompt: userPrompt)
        } catch {
            throw GeminiAnalysisError.analysisFailed(error.localizedDescription)
        }

        let cleaned = stripCodeFences(raw)

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
        • pitch  — intonation accuracy, staying on note, interval accuracy
        • tone   — resonance, warmth, consistency of vocal colour
        • breath — support, phrase length, control, tension signs
        • timing — rhythm, feel, phrasing groove
        • overall — holistic impression, weighted toward pitch and tone

        Scoring guide:
          8–10  Professional or near-professional quality
          6–7   Developing singer with solid technique emerging
          4–5   Amateur with clear fundamentals but significant rough edges
          1–3   Foundational technical issues across multiple areas

        tldr: 2–3 sentences — biggest strength, clearest area to improve, and the single most impactful drill.
        keyMoments: 3–5 timestamped moments (both positives and issues).
        recommendedExerciseNames: choose 4–6 exercises from the provided list that cover the weakest dimensions. \
        If breath, pitch, and tone all need work, include at least one exercise per area. \
        Do not cluster all picks into one category.
        """
    }

    private var lessonSystemPrompt: String {
        """
        You are an expert vocal coach analysing a student's singing lesson from a transcript.
        The transcript contains both teacher instruction and student singing.
        Base ALL scores ONLY on the student's actual singing — exclude teacher demonstrations.

        Evaluate these five dimensions on a 0.0–10.0 scale:
        • pitch  — intonation accuracy in exercises and song attempts
        • tone   — resonance and quality when the student sings
        • breath — support and control during the student's singing
        • timing — rhythm and feel in the student's singing
        • overall — holistic impression of the student's current level

        Scoring guide (student's singing only):
          8–10  Strong technique emerging clearly, taking coaching well
          6–7   Showing improvement and responding to exercises
          4–5   Early stage, fundamentals present but inconsistent
          1–3   Foundational issues across multiple dimensions

        tldr: 2–3 sentences — root cause issue the lesson revealed, what showed progress, and the #1 drill to practise before the next lesson.
        keyMoments: 4–6 timestamped moments covering exercises, breakthroughs, and persistent issues.
        recommendedExerciseNames: choose 4–6 exercises from the provided list that cover the weakest dimensions. \
        Do not cluster all picks into one category.
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
