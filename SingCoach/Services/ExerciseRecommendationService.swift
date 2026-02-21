import Foundation
import SwiftData
import NaturalLanguage
import FoundationModels

// MARK: - Apple Intelligence structured output type

@available(iOS 26.0, *)
@Generable
struct ExerciseRecommendationResult {
    @Guide(description: "Scores 0.0–1.0 for each vocal exercise category based on what the transcript suggests the singer needs work on")
    var warmup: Double
    @Guide(description: "Score for breath support/control exercises")
    var breath: Double
    @Guide(description: "Score for pitch accuracy exercises")
    var pitch: Double
    @Guide(description: "Score for resonance and tone exercises")
    var resonance: Double
    @Guide(description: "Score for range extension exercises")
    var range: Double
    @Guide(description: "Score for articulation and diction exercises")
    var articulation: Double
}

// MARK: - ExerciseRecommendationService

@MainActor
final class ExerciseRecommendationService: ObservableObject {

    // MARK: - Primary: Apple Intelligence (iOS 26, device eligible, AI enabled)

    func recommendExercises(
        transcript: String,
        song: Song,
        allExercises: [Exercise],
        count: Int = 5
    ) -> [Exercise] {
        // Kick off async recommendation — returns seed set immediately, updates later
        // For synchronous callers (stopRecording), we use the blocking path below
        return recommendSync(transcript: transcript, allExercises: allExercises, count: count)
    }

    /// Async version — tries Apple Intelligence first, falls back to NLEmbedding
    func recommendAsync(
        transcript: String,
        song: Song,
        allExercises: [Exercise],
        count: Int = 5
    ) async -> [Exercise] {
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                if let appleIntelligenceResult = await recommendViaAppleIntelligence(
                    transcript: transcript, allExercises: allExercises, count: count) {
                    print("[SingCoach] Exercise recommendation via Apple Intelligence: \(appleIntelligenceResult.count)")
                    AnalyticsService.shared.exerciseRecommended(count: appleIntelligenceResult.count, source: "apple_intelligence")
                    return appleIntelligenceResult
                }
            }
        }
        // Fallback: NLEmbedding semantic similarity
        let result = recommendViaNLEmbedding(transcript: transcript, allExercises: allExercises, count: count)
        AnalyticsService.shared.exerciseRecommended(count: result.count, source: "nl_embedding")
        return result
    }

    // MARK: - Apple Intelligence path

    @available(iOS 26.0, *)
    private func recommendViaAppleIntelligence(
        transcript: String,
        allExercises: [Exercise],
        count: Int
    ) async -> [Exercise]? {
        do {
            let session = LanguageModelSession(
                instructions: """
                You are a vocal coach assistant. Given a transcription of someone singing, \
                score each vocal exercise category from 0.0 to 1.0 based on what areas \
                the singer most likely needs to develop. Consider pitch accuracy, breath \
                support, resonance, range, warmup needs, and articulation. \
                A higher score means higher priority for that category.
                """
            )

            let prompt = """
            Song: "\(transcript.prefix(800))"
            
            Based on this transcription of the singer's performance, score each exercise \
            category to recommend the most helpful exercises.
            """

            let response = try await session.respond(
                to: prompt,
                generating: ExerciseRecommendationResult.self
            )

            let scores: [(category: String, score: Double)] = [
                ("warmup", response.content.warmup),
                ("breath", response.content.breath),
                ("pitch", response.content.pitch),
                ("resonance", response.content.resonance),
                ("range", response.content.range),
                ("articulation", response.content.articulation)
            ].sorted { $0.score > $1.score }

            print("[SingCoach] Apple Intelligence scores: \(scores.map { "\($0.category)=\(String(format: "%.2f", $0.score))" }.joined(separator: ", "))")

            // Pick best exercises from top-scored categories
            var recommended: [Exercise] = []
            for (category, score) in scores where score > 0.1 && recommended.count < count {
                let alreadyIDs = Set(recommended.map { $0.id })
                let candidates = allExercises.filter {
                    $0.category == category && !alreadyIDs.contains($0.id)
                }
                // Take up to 2 from top categories, 1 from lower
                let take = score > 0.6 ? 2 : 1
                recommended.append(contentsOf: candidates.prefix(take))
            }
            return recommended.isEmpty ? nil : Array(recommended.prefix(count))

        } catch {
            print("[SingCoach] Apple Intelligence recommendation failed: \(error) — falling back to NLEmbedding")
            return nil
        }
    }

    // MARK: - NLEmbedding semantic path (all devices)

    private func recommendViaNLEmbedding(
        transcript: String,
        allExercises: [Exercise],
        count: Int
    ) -> [Exercise] {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            print("[SingCoach] NLEmbedding unavailable — using category fallback")
            return categoryFallback(allExercises: allExercises, count: count)
        }

        // Unique meaningful words from transcript (>3 chars, deduplicated)
        let transcriptWords = Array(Set(
            transcript.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 3 }
        )).prefix(60) // cap for performance

        // Score each exercise using max semantic similarity across (transcriptWord × exerciseTerm) pairs
        var scored: [(exercise: Exercise, score: Double)] = allExercises.map { exercise in
            let exerciseTerms = (exercise.keywords + [exercise.name, exercise.category, exercise.focusArea])
                .map { $0.lowercased() }

            var maxSimilarity = 0.0
            for tWord in transcriptWords {
                for eTerm in exerciseTerms {
                    let distance = embedding.distance(between: tWord, and: eTerm)
                    // NLEmbedding distance: 0=identical, higher=more distant (cosine distance 0..2)
                    let similarity = max(0, 1.0 - (distance / 1.5))
                    if similarity > maxSimilarity { maxSimilarity = similarity }
                }
            }
            return (exercise, maxSimilarity)
        }

        scored.sort { $0.score > $1.score }
        let topScored = scored.filter { $0.score > 0.35 }.prefix(count).map { $0.exercise }

        print("[SingCoach] NLEmbedding: top score=\(String(format: "%.3f", scored.first?.score ?? 0)), matched \(topScored.count) exercises")

        // If semantic matching didn't find enough, pad with category fallback
        if topScored.count < count {
            var result = Array(topScored)
            let alreadyIDs = Set(result.map { $0.id })
            let fallback = categoryFallback(allExercises: allExercises, count: count - result.count)
                .filter { !alreadyIDs.contains($0.id) }
            result.append(contentsOf: fallback)
            return Array(result.prefix(count))
        }
        return Array(topScored)
    }

    // MARK: - Synchronous path (called from stopRecording on main thread)
    // Uses NLEmbedding synchronously — Apple Intelligence async path triggered separately

    private func recommendSync(
        transcript: String,
        allExercises: [Exercise],
        count: Int
    ) -> [Exercise] {
        return recommendViaNLEmbedding(transcript: transcript, allExercises: allExercises, count: count)
    }

    // MARK: - Category fallback (always returns something useful)

    private func categoryFallback(allExercises: [Exercise], count: Int) -> [Exercise] {
        let categories = ["warmup", "breath", "pitch", "resonance", "range", "articulation"]
        var result: [Exercise] = []
        for category in categories where result.count < count {
            if let ex = allExercises.first(where: { $0.category == category }) {
                result.append(ex)
            }
        }
        return result
    }

    // MARK: - Legacy (karaoke scoring helpers — kept for compatibility)

    static func stringSimilarity(_ a: String, _ b: String) -> Double {
        let aLower = a.lowercased(), bLower = b.lowercased()
        if aLower == bLower { return 1.0 }
        let aWords = Set(aLower.components(separatedBy: .whitespaces))
        let bWords = Set(bLower.components(separatedBy: .whitespaces))
        let intersection = aWords.intersection(bWords).count
        let union = aWords.union(bWords).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    static func karaokeScore(candidateTitle: String, originalTitle: String) -> Double {
        let karaokeKeywords = ["karaoke", "instrumental", "backing track", "minus one", "no vocals"]
        let titleLower = candidateTitle.lowercased()
        let hasKaraokeKeyword = karaokeKeywords.contains { titleLower.contains($0) }
        let similarityScore = stringSimilarity(
            titleLower.replacingOccurrences(of: "karaoke", with: "").replacingOccurrences(of: "instrumental", with: ""),
            originalTitle.lowercased()
        )
        return (hasKaraokeKeyword ? 0.5 : 0.0) + (similarityScore * 0.5)
    }
}
