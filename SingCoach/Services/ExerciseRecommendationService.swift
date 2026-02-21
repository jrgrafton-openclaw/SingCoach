import Foundation
import SwiftData

@MainActor
final class ExerciseRecommendationService: ObservableObject {

    // Recommendation strategy:
    // 1. Keyword match transcript words against exercise keywords (works if transcript has coaching terms)
    // 2. Fallback: singing transcripts contain lyrics, not coaching words — always recommend
    //    one exercise per category (covering all bases) so users always get something useful.
    func recommendExercises(
        transcript: String,
        song: Song,
        allExercises: [Exercise],
        count: Int = 5
    ) -> [Exercise] {
        let transcriptWords = Set(
            transcript.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
        )

        var scored: [(exercise: Exercise, score: Int)] = allExercises.compactMap { exercise in
            let keywordSet = Set(exercise.keywords.map { $0.lowercased() })
            let overlap = keywordSet.intersection(transcriptWords).count
            return overlap > 0 ? (exercise, overlap) : nil
        }
        scored.sort { $0.score > $1.score }
        var recommended = Array(scored.prefix(count).map { $0.exercise })

        // Fallback: singing transcripts contain lyrics not coaching terms — pick one per
        // category so the user always gets actionable exercise recommendations.
        if recommended.count < count {
            let categories = ["warmup", "breath", "pitch", "resonance", "range"]
            for category in categories where recommended.count < count {
                let alreadyIDs = Set(recommended.map { $0.id })
            if let ex = allExercises.first(where: {
                    $0.category == category && !alreadyIDs.contains($0.id)
                }) {
                    recommended.append(ex)
                }
            }
        }

        print("[SingCoach] Exercise recommendation: \(recommended.count) exercises (keyword matches: \(scored.count))")
        AnalyticsService.shared.exerciseRecommended(count: recommended.count, source: scored.isEmpty ? "category_fallback" : "keyword_match")

        return recommended
    }

    // String similarity scoring for karaoke matching
    static func stringSimilarity(_ a: String, _ b: String) -> Double {
        let aLower = a.lowercased()
        let bLower = b.lowercased()
        if aLower == bLower { return 1.0 }

        let aWords = Set(aLower.components(separatedBy: .whitespaces))
        let bWords = Set(bLower.components(separatedBy: .whitespaces))
        let intersection = aWords.intersection(bWords).count
        let union = aWords.union(bWords).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    // Score a karaoke search result against the original song title
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
