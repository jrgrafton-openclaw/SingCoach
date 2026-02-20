import SwiftUI
import SwiftData

struct SongDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let song: Song
    @StateObject private var recordingVM = RecordingViewModel()
    @State private var selectedTab = 0
    @State private var showExerciseBrowser = false

    var body: some View {
        ZStack {
            SingCoachTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    SongHeaderView(song: song) {
                        recordingVM.showRecordingSheet = true
                    }

                    // Tab selector
                    SectionTabBar(selectedTab: $selectedTab, tabs: ["Lyrics", "Lessons", "Exercises"])
                        .padding(.top, 16)

                    // Content
                    switch selectedTab {
                    case 0:
                        LyricsView(song: song)
                            .padding(.top, 8)
                    case 1:
                        LessonsSection(song: song, recordingVM: recordingVM)
                            .padding(.top, 8)
                    case 2:
                        ExercisesSection(song: song)
                            .padding(.top, 8)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            recordingVM.configure(song: song, modelContext: modelContext)
        }
        .sheet(isPresented: $recordingVM.showRecordingSheet) {
            RecordingSheet(song: song, viewModel: recordingVM)
        }
    }
}

struct SongHeaderView: View {
    let song: Song
    let onRecord: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(SingCoachTheme.primaryGradient)
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(SingCoachTheme.accent)
            }

            Text(song.title)
                .font(SingCoachTheme.headerFont())
                .foregroundColor(SingCoachTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(song.artist)
                .font(.system(size: 16))
                .foregroundColor(SingCoachTheme.textSecondary)

            Button(action: onRecord) {
                Label("Record Lesson", systemImage: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(SingCoachTheme.accent)
                    .foregroundColor(.black)
                    .cornerRadius(20)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
    }
}

struct SectionTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab)
                            .font(.system(size: 14, weight: selectedTab == index ? .semibold : .regular))
                            .foregroundColor(selectedTab == index ? SingCoachTheme.accent : SingCoachTheme.textSecondary)
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(selectedTab == index ? SingCoachTheme.accent : .clear)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct LessonsSection: View {
    let song: Song
    @ObservedObject var recordingVM: RecordingViewModel

    var sortedLessons: [Lesson] {
        song.lessons.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if song.lessons.isEmpty {
                EmptyStateView(
                    icon: "mic.slash",
                    title: "No Lessons Yet",
                    subtitle: "Record your first lesson to get started"
                )
                .padding(.top, 40)
            } else {
                ForEach(sortedLessons) { lesson in
                    LessonRowView(lesson: lesson)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct LessonRowView: View {
    let lesson: Lesson
    @StateObject private var player = AudioPlaybackService()
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.date, style: .date)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SingCoachTheme.textPrimary)
                    HStack(spacing: 6) {
                        Text(formatDuration(lesson.durationSeconds))
                            .font(.system(size: 12))
                            .foregroundColor(SingCoachTheme.textSecondary)
                        if lesson.status != .done {
                            Text(lesson.status.displayText)
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SingCoachTheme.accent.opacity(0.2))
                                .foregroundColor(SingCoachTheme.accent)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                Button {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        if let url = URL(string: lesson.audioFileURL) {
                            try? player.load(url: url)
                            player.play()
                        }
                    }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(SingCoachTheme.accent)
                }
            }

            if player.isPlaying || player.currentTime > 0 {
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    .tint(SingCoachTheme.accent)

                    HStack {
                        Text(formatDuration(player.currentTime))
                        Spacer()
                        Text(formatDuration(player.duration))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(SingCoachTheme.textSecondary)
                }
            }

            if let transcript = lesson.transcript, !transcript.isEmpty {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text("Transcript")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(SingCoachTheme.textSecondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }
                }

                if isExpanded {
                    Text(transcript)
                        .font(.system(size: 13))
                        .foregroundColor(SingCoachTheme.textSecondary)
                        .lineLimit(nil)
                }
            }
        }
        .padding(14)
        .background(SingCoachTheme.surface)
        .cornerRadius(12)
    }

    func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct ExercisesSection: View {
    let song: Song

    var recommendedExercises: [Exercise] {
        song.mostRecentLesson?.recommendedExercises ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !recommendedExercises.isEmpty {
                Text("Recommended")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SingCoachTheme.accent)
                    .padding(.horizontal, 16)

                ForEach(recommendedExercises) { exercise in
                    ExerciseRowView(exercise: exercise)
                        .padding(.horizontal, 16)
                }
            } else {
                EmptyStateView(
                    icon: "figure.mixed.cardio",
                    title: "No Exercises Yet",
                    subtitle: "Record a lesson to get personalised recommendations"
                )
                .padding(.top, 40)
            }
        }
    }
}
