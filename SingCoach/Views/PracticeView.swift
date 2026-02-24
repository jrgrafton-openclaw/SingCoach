import SwiftUI
import SwiftData

// MARK: - Practice stats helpers (used by PracticeView)

private extension [PracticeEntry] {
    var currentStreak: Int {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())
        let days = Set(self.map { Calendar.current.startOfDay(for: $0.date) })
        while days.contains(checkDate) {
            streak += 1
            checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }

    var thisWeekCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return self.filter { $0.date >= cutoff }.count
    }

    var topCategory: String? {
        let counts = Dictionary(grouping: self, by: \.exerciseCategory)
            .mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

struct PracticeView: View {
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]
    @Query(sort: \Exercise.createdAt, order: .reverse) private var allExercises: [Exercise]
    @Query(sort: \PracticeEntry.date, order: .reverse) private var practiceHistory: [PracticeEntry]

    // Exercises from the most recent recording (lesson OR performance) that has AI recommendations.
    // Previously used mostRecentLesson which filtered out performances — fixed.
    var practiceGroups: [(song: Song, exercises: [Exercise])] {
        songs.compactMap { song in
            let exercises = song.mostRecentRecordingWithExercises?.recommendedExercises ?? []
            guard !exercises.isEmpty else { return nil }
            return (song, exercises)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        // ── Stats strip ──────────────────────────────────────────
                        if !practiceHistory.isEmpty {
                            PracticeStatsView(history: practiceHistory)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        // ── Today's recommended exercises ─────────────────────────
                        if practiceGroups.isEmpty {
                            EmptyStateView(
                                icon: "flame",
                                title: "Nothing to Practice",
                                subtitle: "Record a lesson or performance to get AI exercise recommendations"
                            )
                            .padding(.top, practiceHistory.isEmpty ? 60 : 0)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("RECOMMENDED")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(SingCoachTheme.textSecondary)
                                    .tracking(1.2)
                                    .padding(.horizontal, 16)
                                ForEach(practiceGroups, id: \.song.id) { group in
                                    PracticeGroupView(song: group.song, exercises: group.exercises)
                                }
                            }
                            .padding(.top, 4)
                        }

                        // ── Practice history ──────────────────────────────────────
                        if !practiceHistory.isEmpty {
                            PracticeHistoryView(history: Array(practiceHistory.prefix(20)))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 20)
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
                .padding(.horizontal, 16)

            ForEach(exercises) { exercise in
                // Pass the lesson ID so PracticeEntry can reference the source recording
                ExerciseRowView(
                    exercise: exercise,
                    lessonID: song.mostRecentRecordingWithExercises?.id
                )
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Stats strip

struct PracticeStatsView: View {
    let history: [PracticeEntry]

    var body: some View {
        // Equal-width cards — no scroll needed (4 cards max)
        HStack(spacing: 10) {
            StatCard(icon: "flame.fill", iconColor: .orange,
                     value: "\(history.currentStreak)", label: "day streak")
            StatCard(icon: "checkmark.circle.fill", iconColor: .green,
                     value: "\(history.thisWeekCount)", label: "this week")
            StatCard(icon: "star.fill", iconColor: SingCoachTheme.accent,
                     value: "\(history.count)", label: "all time")
            if let top = history.topCategory {
                StatCard(icon: "trophy.fill", iconColor: .yellow,
                         value: ExerciseCategory(rawValue: top)?.displayName ?? top.capitalized,
                         label: "top category")
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(SingCoachTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SingCoachTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(SingCoachTheme.surface)
        .cornerRadius(12)
    }
}

// MARK: - Practice history

struct PracticeHistoryView: View {
    let history: [PracticeEntry]
    @Environment(\.modelContext) private var modelContext

    /// Groups entries by calendar day, most recent day first.
    private var grouped: [(date: Date, entries: [PracticeEntry])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: history) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in (day, byDay[day]!.sorted { $0.date > $1.date }) }
    }

    private func formatGroupDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private func deleteEntry(_ entry: PracticeEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SingCoachTheme.textSecondary)
                .tracking(1.2)
                .padding(.horizontal, 16)

            ForEach(grouped, id: \.date) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatGroupDate(group.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SingCoachTheme.textSecondary)
                        .padding(.horizontal, 16)

                    // SwipeToDeleteRow works inside ScrollView (List inside ScrollView breaks swipe)
                    VStack(spacing: 6) {
                        ForEach(group.entries) { entry in
                            SwipeToDeleteRow(onDelete: { deleteEntry(entry) }) {
                                PracticeHistoryEntryRow(entry: entry)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Swipe-to-delete wrapper (works inside ScrollView; List inside ScrollView breaks swipe)

struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var isOpen = false
    private let deleteButtonWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            // Red delete zone — visible when swiped left
            Button(action: {
                snap(to: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onDelete() }
            }) {
                ZStack {
                    Color.red
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: abs(min(dragOffset, 0)))
            .cornerRadius(10)

            content()
                // Ensure the full row background area is hittable
                .contentShape(Rectangle())
                .offset(x: dragOffset)
                // highPriorityGesture so the drag isn't stolen by the outer ScrollView
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // Only track horizontal-dominant drags
                            guard abs(value.translation.width) > abs(value.translation.height) * 0.7 else { return }
                            let base: CGFloat = isOpen ? -deleteButtonWidth : 0
                            dragOffset = min(0, max(base + value.translation.width, -deleteButtonWidth))
                        }
                        .onEnded { value in
                            let swipeDistance = value.translation.width
                            let predictedEnd = value.predictedEndTranslation.width
                            if swipeDistance < -(deleteButtonWidth * 0.3) || predictedEnd < -deleteButtonWidth {
                                snap(to: -deleteButtonWidth)
                            } else {
                                snap(to: 0)
                            }
                        }
                )
        }
        .clipped()
        // Tap anywhere on the ZStack to close if open
        .onTapGesture {
            if isOpen { snap(to: 0) }
        }
    }

    private func snap(to offset: CGFloat) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = offset
            isOpen = offset != 0
        }
    }
}

// MARK: - Practice history entry row

struct PracticeHistoryEntryRow: View {
    let entry: PracticeEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exerciseName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SingCoachTheme.textPrimary)
                Text(ExerciseCategory(rawValue: entry.exerciseCategory)?.displayName
                     ?? entry.exerciseCategory.capitalized)
                    .font(.system(size: 11))
                    .foregroundColor(SingCoachTheme.textSecondary)
            }
            Spacer()
            Text(entry.date, style: .time)
                .font(.system(size: 11))
                .foregroundColor(SingCoachTheme.textSecondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(SingCoachTheme.surface)
        .cornerRadius(10)
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise
    var lessonID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
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
        .onAppear { loadTodayState() }
        .sheet(isPresented: $showDetail) {
            ExerciseDetailSheet(exercise: exercise, onMarkPracticed: {
                markPracticed()
            })
        }
    }

    private func loadTodayState() {
        let today = Calendar.current.startOfDay(for: Date())
        let tmpl = exercise.templateID ?? exercise.name
        let desc = FetchDescriptor<PracticeEntry>(
            predicate: #Predicate { $0.exerciseTemplateID == tmpl && $0.date >= today }
        )
        practiced = ((try? modelContext.fetch(desc))?.isEmpty == false)
    }

    private func markPracticed() {
        guard !practiced else { return }
        practiced = true
        let entry = PracticeEntry(
            exerciseTemplateID: exercise.templateID ?? exercise.name,
            exerciseName: exercise.name,
            exerciseCategory: exercise.category,
            lessonID: lessonID
        )
        modelContext.insert(entry)
        try? modelContext.save()
        AnalyticsService.shared.exercisePracticed(
            category: exercise.category,
            templateID: exercise.templateID ?? "unknown"
        )
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
