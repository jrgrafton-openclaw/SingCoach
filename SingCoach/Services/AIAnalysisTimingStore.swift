import Foundation

/// Persists (audioSec, actualSec) samples from real AI analysis runs and provides
/// a self-tuning duration estimate for the UI's progress bar.
///
/// Why mean and not linear regression: empirically the relationship between audio
/// length and analysis time is dominated by Vertex API latency variance, not audio
/// length. Two early production data points (13min→70s, 25min→50s) show inverse
/// correlation, confirming length is not predictive. A rolling mean of recent runs
/// outperforms any synthetic benchmark because it reflects real network conditions.
@MainActor
final class AIAnalysisTimingStore {
    static let shared = AIAnalysisTimingStore()

    private let key = "ai_analysis_timing_samples_v1"
    private let maxSamples = 20
    private let defaultEstimateSeconds = 60

    struct Sample: Codable {
        let audioSec: Double
        let actualSec: Double
        let date: Date
    }

    private init() {}

    var samples: [Sample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Sample].self, from: data)
        else { return [] }
        return decoded
    }

    func record(audioSec: Double, actualSec: Double) {
        var current = samples
        current.append(Sample(audioSec: audioSec, actualSec: actualSec, date: Date()))
        // Keep only the most recent N — older data may reflect retired model versions.
        let trimmed = Array(current.suffix(maxSamples))
        if let encoded = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        print("[SingCoach] timing recorded: audio=\(Int(audioSec))s actual=\(Int(actualSec))s | sample count=\(trimmed.count) | new mean=\(estimate(audioSeconds: audioSec))s")
    }

    /// Returns an estimated number of seconds the Pro analysis will take.
    /// Audio length is currently ignored because empirical data shows Vertex latency
    /// dominates. Returns 60s default until we have at least 3 samples.
    func estimate(audioSeconds: Double) -> Int {
        let s = samples
        guard s.count >= 3 else { return defaultEstimateSeconds }
        let mean = s.map(\.actualSec).reduce(0, +) / Double(s.count)
        return max(20, Int(mean.rounded()))
    }
}
