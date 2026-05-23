import Foundation
import FirebaseAI

// MARK: - Text Generator Protocol
// Abstracts the Firebase generateContent call so tests can inject a mock
// without needing access to Firebase SDK internals.

protocol AITextGenerator: Sendable {
    /// Sends audio bytes + a text prompt to the model in one request, returns the text response.
    /// This is the single-call architecture: Pro listens to the audio AND scores it.
    func generateText(audioData: Data, mimeType: String, prompt: String) async throws -> String
}

// Production implementation backed by a real Firebase GenerativeModel
struct FirebaseTextGenerator: AITextGenerator {
    let model: GenerativeModel

    func generateText(audioData: Data, mimeType: String, prompt: String) async throws -> String {
        let audioPart = InlineDataPart(data: audioData, mimeType: mimeType)
        let response = try await model.generateContent(audioPart, prompt)

        // Surface the most useful failure reason we can extract from the response.
        if let block = response.promptFeedback?.blockReason {
            let extra = response.promptFeedback?.blockReasonMessage.map { ": \($0)" } ?? ""
            throw GeminiAnalysisError.analysisFailed("Prompt blocked (\(block.rawValue))\(extra)")
        }
        if let candidate = response.candidates.first,
           let reason = candidate.finishReason,
           reason != .stop {
            throw GeminiAnalysisError.analysisFailed("Model stopped early: \(reason.rawValue)")
        }
        guard let text = response.text else {
            throw GeminiAnalysisError.analysisFailed("Empty response (no candidates returned)")
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

/// Sendable summary of an Exercise — used to pass the library across actor boundaries
/// into `analyze(...)` (which is nonisolated) without crossing a `@Model` over the wire.
struct AIExerciseSummary: Sendable {
    let name: String
    let category: String
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

// MARK: - Progress

/// Stages reported via `onProgress` during `analyze(...)`. UI binds to this to show
/// the user where in the pipeline we are.
enum AnalysisStage: Sendable, Equatable {
    case loadingAudio(sizeMB: Double)
    case transcribing
    case analyzing
    case matchingExercises
    case saving

    var displayText: String {
        switch self {
        case .loadingAudio(let mb):
            return "Loading audio (\(String(format: "%.1f", mb)) MB)…"
        case .transcribing:
            return "Transcribing audio…"
        case .analyzing:
            return "Scoring performance…"
        case .matchingExercises:
            return "Choosing exercises…"
        case .saving:
            return "Saving results…"
        }
    }
}

typealias AnalysisProgressCallback = @Sendable @MainActor (AnalysisStage) -> Void

// MARK: - Service

final class GeminiAnalysisService {

    private let maxFileSizeBytes = 19 * 1024 * 1024 // 19 MB safety margin

    // Overrideable for testing; nil = use real Firebase model
    private let proGenerator: AITextGenerator?

    /// Production init — uses real Firebase Vertex AI model.
    init() {
        self.proGenerator = nil
    }

    /// Test init — inject mock generator to avoid real Firebase HTTP calls.
    init(proGenerator: any AITextGenerator) {
        self.proGenerator = proGenerator
    }

    /// Builds a `GenerativeModel` whose response is constrained to valid JSON matching the
    /// `AIAnalysisResponse` schema, with `recommendedExerciseNames` locked to the provided list.
    /// Pro 3.x listens to the audio AND scores it in one call — no separate transcription pass.
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
                "transcript": .string(description: "Full transcript of what was sung/spoken, with [M:SS] markers at each paragraph or scene change"),
                "overall":   .double(description: "0.0–10.0 holistic score based on what was actually heard"),
                "pitch":     .double(description: "0.0–10.0 intonation score based on actual pitch accuracy heard"),
                "tone":      .double(description: "0.0–10.0 resonance / vocal colour score based on actual sound heard"),
                "breath":    .double(description: "0.0–10.0 breath support score based on phrase endings and tension heard"),
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

    /// Wire-format struct matching the Pro response schema (transcript + analysis fields).
    /// Split into `AIAnalysisResult` + `transcript` String after decoding so the stored
    /// `aiAnalysis` JSON on `Lesson` stays backwards-compatible.
    private struct AIAnalysisResponse: Codable {
        var transcript: String
        var overall: Double
        var pitch: Double
        var tone: Double
        var breath: Double
        var timing: Double
        var tldr: String
        var keyMoments: [AIKeyMoment]
        var recommendedExerciseNames: [String]
    }

    // MARK: - Public API

    /// Full pipeline: single Pro 3.1 call with audio + analysis prompt.
    /// Pro listens to the audio AND scores it acoustically (pitch, tone, breath all derived
    /// from the actual sound, not just a text transcript). Returns the transcript plus the
    /// structured analysis. Accepts primitives (no SwiftData models) so it is safe to call
    /// across actor boundaries. Pass `onProgress` to receive stage updates for UI display.
    func analyze(
        audioFileURL: String,
        isPerformance: Bool,
        exerciseLibrary: [AIExerciseSummary],
        onProgress: AnalysisProgressCallback? = nil
    ) async throws -> (result: AIAnalysisResult, transcript: String) {

        let audioURL = AudioPathResolver.resolvedURL(audioFileURL)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw GeminiAnalysisError.audioFileNotFound
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        if fileSize > maxFileSizeBytes {
            throw GeminiAnalysisError.audioFileTooLarge(sizeMB: Double(fileSize) / 1_048_576)
        }

        await report(onProgress, .loadingAudio(sizeMB: Double(fileSize) / 1_048_576))

        let audioData = try Data(contentsOf: audioURL)
        let mimeType = Self.mimeType(for: audioURL)

        await report(onProgress, .analyzing)
        let response = try await runProAnalysis(
            audioData: audioData,
            mimeType: mimeType,
            isPerformance: isPerformance,
            exerciseLibrary: exerciseLibrary
        )

        await report(onProgress, .matchingExercises)
        let result = AIAnalysisResult(
            overall: response.overall,
            pitch: response.pitch,
            tone: response.tone,
            breath: response.breath,
            timing: response.timing,
            tldr: response.tldr,
            keyMoments: response.keyMoments,
            recommendedExerciseNames: response.recommendedExerciseNames
        )
        return (result, response.transcript)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":  return "audio/mpeg"
        case "wav":  return "audio/wav"
        case "aac":  return "audio/aac"
        default:     return "audio/mp4"  // m4a, mp4
        }
    }

    private func report(_ cb: AnalysisProgressCallback?, _ stage: AnalysisStage) async {
        guard let cb else { return }
        await cb(stage)
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

    // MARK: - Single Pro call (audio + analysis prompt)

    private func runProAnalysis(
        audioData: Data,
        mimeType: String,
        isPerformance: Bool,
        exerciseLibrary: [AIExerciseSummary]
    ) async throws -> AIAnalysisResponse {

        let exerciseNames = exerciseLibrary.map(\.name)
        // Model is created with a response schema that constrains recommendedExerciseNames
        // to exactly the exercise names in the library — no fuzzy matching needed.
        let generator = makeProGenerator(isPerformance: isPerformance, exerciseNames: exerciseNames)

        let exerciseList = exerciseLibrary.isEmpty
            ? "(no exercises in library yet)"
            : exerciseLibrary.map { "- \($0.name) [\($0.category)]" }.joined(separator: "\n")

        let userPrompt = """
        Listen to the attached audio and produce the structured analysis described in the system instruction.
        Base your pitch, tone, breath, and timing scores on what you can actually hear in the audio,
        not on the words being sung. Include an accurate timestamped transcript in the `transcript` field.

        AVAILABLE EXERCISES (use EXACT names when recommending):
        \(exerciseList)

        Respond with ONLY the JSON object. No markdown fences, no explanation.
        """

        let raw: String
        do {
            raw = try await withRetry {
                try await generator.generateText(audioData: audioData, mimeType: mimeType, prompt: userPrompt)
            }
        } catch let e as GeminiAnalysisError {
            throw e
        } catch {
            throw GeminiAnalysisError.analysisFailed(Self.describe(error))
        }

        let cleaned = stripCodeFences(raw)

        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiAnalysisError.invalidResponse("Could not encode response as UTF-8")
        }

        do {
            return try JSONDecoder().decode(AIAnalysisResponse.self, from: data)
        } catch {
            throw GeminiAnalysisError.invalidResponse("JSON decode failed: \(error.localizedDescription). First 300 chars: \(String(cleaned.prefix(300)))")
        }
    }

    // MARK: - Error description & retry

    /// Pull every useful detail out of an error from Firebase AI / URL session.
    /// Surfaces NSError domain+code, underlying chain, and any text body so the user
    /// sees something more actionable than "FirebaseAiGenerateContent error 0".
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts: [String] = []
        parts.append("\(ns.domain) code \(ns.code)")
        let msg = error.localizedDescription
        if !msg.isEmpty, !msg.contains("code \(ns.code)") {
            parts.append(msg)
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
        }
        // FirebaseAI often stuffs server text into userInfo under various keys.
        for (key, value) in ns.userInfo where !["NSUnderlyingError"].contains(key) {
            if let s = value as? String, !s.isEmpty, !parts.contains(s) {
                parts.append("\(key): \(String(s.prefix(200)))")
            }
        }
        return parts.joined(separator: " | ")
    }

    /// One retry with backoff for transient network / 5xx / rate-limit failures.
    private func withRetry<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            let ns = error as NSError
            let msg = error.localizedDescription.lowercased()
            let transient = ns.domain == NSURLErrorDomain
                || (500...599).contains(ns.code)
                || msg.contains("rate")
                || msg.contains("timeout")
                || msg.contains("unavailable")
                || msg.contains("temporarily")
            guard transient else { throw error }
            print("[SingCoach] Gemini call transient failure, retrying once: \(Self.describe(error))")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return try await operation()
        }
    }

    // MARK: - Prompts

    private var performanceSystemPrompt: String {
        """
        You are an expert vocal coach evaluating a student's solo singing performance from an audio recording.
        Listen to the audio carefully. Your scores must reflect what you actually hear, not assumptions
        about the song or words.

        First, produce an accurate transcript of what is sung, inserting [M:SS] timestamp markers at the
        start of each new section, verse, or notable change. Put this in the `transcript` field.

        Then evaluate these five dimensions on a 0.0–10.0 scale based on the actual sound:
        • pitch  — intonation accuracy, staying on note, interval accuracy
        • tone   — resonance, warmth, consistency of vocal colour
        • breath — support, phrase length, control, audible tension or breath noise
        • timing — rhythm, feel, phrasing groove
        • overall — holistic impression, weighted toward pitch and tone

        Scoring guide:
          8–10  Professional or near-professional quality
          6–7   Developing singer with solid technique emerging
          4–5   Amateur with clear fundamentals but significant rough edges
          1–3   Foundational technical issues across multiple areas

        tldr: 2–3 sentences — biggest strength, clearest area to improve, and the single most impactful drill.
        keyMoments: 3–5 timestamped moments referencing what you heard (both positives and issues).
        recommendedExerciseNames: choose 4–6 exercises from the provided list that cover the weakest dimensions. \
        If breath, pitch, and tone all need work, include at least one exercise per area. \
        Do not cluster all picks into one category.
        """
    }

    private var lessonSystemPrompt: String {
        """
        You are an expert vocal coach analysing a student's singing lesson from an audio recording.
        The audio contains both teacher instruction and student singing/exercises.
        Base ALL scores ONLY on the student's actual singing — exclude teacher demonstrations and speech.

        First, produce an accurate transcript with [M:SS] timestamp markers at section boundaries
        and put it in the `transcript` field. Distinguish teacher from student in the transcript when clear.

        Then evaluate these five dimensions on a 0.0–10.0 scale based on the student's actual singing:
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
