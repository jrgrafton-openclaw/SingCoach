import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAnalytics

@main
struct SingCoachApp: App {
    @StateObject private var exerciseSeeder = ExerciseSeeder()
    // Bug 6 fix: shared RecordingViewModel injected as environment object
    @StateObject private var recordingVM = RecordingViewModel()

    init() {
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        print("[SingCoach] App initialised, Firebase configured")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [Song.self, Lesson.self, Exercise.self, LyricsLine.self, PracticeEntry.self]) { result in
                    // BUG 3 FIX: Seed exercises AFTER the ModelContainer is fully ready
                    switch result {
                    case .success(let container):
                        Task { @MainActor in
                            exerciseSeeder.seedIfNeeded(context: container.mainContext)
                        }
                    case .failure(let error):
                        print("[SingCoach] ModelContainer failed: \(error)")
                    }
                }
                .environmentObject(recordingVM)
                .preferredColorScheme(.dark)
        }
    }
}
