import SwiftUI
import SwiftData

struct PracticeView: View {
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]
    @Query(sort: \Exercise.createdAt, order: .reverse) private var allExercises: [Exercise]

    // All exercises recommended from the most recent lesson of any song
    var practiceGroups: [(song: Song, exercises: [Exercise])] {
        songs.compactMap { song in
            let exercises = song.mostRecentLesson?.recommendedExercises ?? []
            guard !exercises.isEmpty else { return nil }
            return (song, exercises)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                if practiceGroups.isEmpty {
                    EmptyStateView(
                        icon: "flame",
                        title: "Nothing to Practice",
                        subtitle: "Record a lesson to get personalized exercise recommendations"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(practiceGroups, id: \.song.id) { group in
                                PracticeGroupView(song: group.song, exercises: group.exercises)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Practice")
        }
        .preferredColorScheme(.dark)
    }
}

struct PracticeGroupView: View {
    let song: Song
    let exercises: [Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(song.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SingCoachTheme.accent)
                .padding(.horizontal, 4)

            ForEach(exercises) { exercise in
                ExerciseRowView(exercise: exercise)
            }
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise
    @State private var showDetail = false
    @State private var practiced = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(practiced ? SingCoachTheme.textSecondary : SingCoachTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        CategoryBadge(category: exercise.category)
                        DifficultyBadge(difficulty: exercise.difficulty)
                        Text("\(exercise.durationMinutes) min")
                            .font(.system(size: 11))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }
                }

                Spacer()

                if practiced {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
            .padding(14)
            .background(SingCoachTheme.surface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            ExerciseDetailSheet(exercise: exercise, onMarkPracticed: {
                practiced = true
                AnalyticsService.shared.exercisePracticed(
                    category: exercise.category,
                    templateID: exercise.templateID ?? "unknown"
                )
            })
        }
    }
}

struct CategoryBadge: View {
    let category: String

    var body: some View {
        Text(ExerciseCategory(rawValue: category)?.displayName ?? category.capitalized)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(SingCoachTheme.gradientEnd)
            .foregroundColor(SingCoachTheme.accent)
            .cornerRadius(4)
    }
}

struct DifficultyBadge: View {
    let difficulty: String

    var color: Color {
        switch difficulty {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return SingCoachTheme.textSecondary
        }
    }

    var body: some View {
        Text(difficulty.capitalized)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
