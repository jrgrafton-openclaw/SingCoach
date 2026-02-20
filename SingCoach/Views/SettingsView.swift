import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var songs: [Song]
    @Query private var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Stats
                        SectionCard(title: "Your Stats") {
                            HStack(spacing: 20) {
                                StatBlock(value: "\(songs.count)", label: "Songs")
                                Divider().frame(height: 40)
                                StatBlock(value: "\(songs.flatMap { $0.lessons }.count)", label: "Lessons")
                                Divider().frame(height: 40)
                                StatBlock(value: "\(exercises.count)", label: "Exercises")
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // About
                        SectionCard(title: "About") {
                            VStack(alignment: .leading, spacing: 8) {
                                SettingsRow(icon: "music.mic", label: "SingCoach", value: "v1.0")
                                SettingsRow(icon: "brain", label: "On-device AI", value: "Enabled")
                                SettingsRow(icon: "waveform", label: "Transcription", value: "On-device")
                            }
                        }

                        // Exercise library
                        SectionCard(title: "Exercise Library") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                                    let count = exercises.filter { $0.category == category.rawValue }.count
                                    SettingsRow(
                                        icon: category.sfSymbol,
                                        label: category.displayName,
                                        value: "\(count)"
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
        }
        .preferredColorScheme(.dark)
    }
}

struct StatBlock: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(SingCoachTheme.accent)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(SingCoachTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(SingCoachTheme.accent)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(SingCoachTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(SingCoachTheme.textSecondary)
        }
    }
}
