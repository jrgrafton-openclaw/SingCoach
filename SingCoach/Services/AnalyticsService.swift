import Foundation
import FirebaseAnalytics

@MainActor
protocol AnalyticsTracking {
    func logEvent(_ name: String, parameters: [String: Any]?)
}

@MainActor
final class FirebaseAnalyticsTracker: AnalyticsTracking {
    func logEvent(_ name: String, parameters: [String: Any]?) {
        Analytics.logEvent(name, parameters: parameters)
        print("[SingCoach] Analytics event: \(name) params=\(parameters ?? [:])")
    }
}

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()
    var tracker: AnalyticsTracking = FirebaseAnalyticsTracker()

    private init() {}

    func songAdded(source: String, hasSyncedLyrics: Bool) {
        tracker.logEvent("song_added", parameters: [
            "source": source,
            "has_synced_lyrics": hasSyncedLyrics
        ])
    }

    func lessonRecorded(durationSeconds: Double) {
        tracker.logEvent("lesson_recorded", parameters: [
            "duration_seconds": durationSeconds
        ])
    }

    func lessonTranscribed(success: Bool, wordCount: Int) {
        tracker.logEvent("lesson_transcribed", parameters: [
            "success": success,
            "word_count": wordCount
        ])
    }

    func exerciseRecommended(count: Int, source: String) {
        tracker.logEvent("exercise_recommended", parameters: [
            "count": count,
            "source": source
        ])
    }

    func karaokeTrackSelected(wasFuzzyMatch: Bool, userOverrode: Bool) {
        tracker.logEvent("karaoke_track_selected", parameters: [
            "was_fuzzy_match": wasFuzzyMatch,
            "user_overrode": userOverrode
        ])
    }

    func exercisePracticed(category: String, templateID: String) {
        tracker.logEvent("exercise_practiced", parameters: [
            "category": category,
            "template_id": templateID
        ])
    }
}
