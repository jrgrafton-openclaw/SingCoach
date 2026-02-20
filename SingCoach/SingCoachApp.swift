import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAnalytics

@main
struct SingCoachApp: App {
    @StateObject private var exerciseSeeder = ExerciseSeeder()

    init() {
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        print("[SingCoach] App initialised, Firebase configured")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [Song.self, Lesson.self, Exercise.self, LyricsLine.self])
                .preferredColorScheme(.dark)
                .onAppear {
                    exerciseSeeder.seedIfNeeded()
                }
        }
    }
}
