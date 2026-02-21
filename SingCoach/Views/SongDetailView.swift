import SwiftUI
import SwiftData
import MusicKit
import Combine

// Bug 5 fix: RecordingType enum now lives here (not inside RecordingSheet)
enum RecordingType: String, CaseIterable {
    case lesson = "Lesson"
    case performance = "Performance"
}

// MARK: - Cached Image Loader (Bug 7 fix)

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage? = nil
    private var currentURL: String?

    func load(urlString: String) {
        guard urlString != currentURL else { return }
        currentURL = urlString
        guard let url = URL(string: urlString) else { return }
        // Check URLCache first to avoid flash on re-navigation
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        if let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let uiImage = UIImage(data: cached) {
            self.image = uiImage
            return
        }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let cachedResponse = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cachedResponse, for: URLRequest(url: url))
                if let uiImage = UIImage(data: data) {
                    await MainActor.run { self.image = uiImage }
                }
            } catch { }
        }
    }
}

// MARK: - SongDetailView

struct SongDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let song: Song
    // Bug 6 fix: use shared RecordingViewModel from environment
    @EnvironmentObject private var recordingVM: RecordingViewModel
    @State private var selectedTab = 0
    @State private var showDeleteConfirm = false
    @State private var showFindBackingTrack = false
    // Bug 5 fix: inline recorder state
    @State private var showInlineRecorder = false
    @State private var selectedRecordingType: RecordingType = .lesson

    var body: some View {
        ZStack {
            SingCoachTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header — Bug 4 fix: pass recordingVM so button reflects recording state
                    SongHeaderView(
                        song: song,
                        onRecord: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showInlineRecorder = true
                            }
                        },
                        showFindBackingTrack: $showFindBackingTrack,
                        recordingVM: recordingVM
                    )

                    // Bug 5 fix: inline recorder panel (replaces sheet)
                    if showInlineRecorder {
                        InlineRecorderView(
                            song: song,
                            recordingVM: recordingVM,
                            selectedType: $selectedRecordingType,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showInlineRecorder = false
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(SingCoachTheme.destructive)
                }
            }
        }
        .confirmationDialog("Delete \"\(song.title)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Song", role: .destructive) {
                deleteSong(song)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the song, all lessons, exercises, and lyrics permanently.")
        }
        .onAppear {
            recordingVM.configure(song: song, modelContext: modelContext)
        }
        // Bug 5 fix: removed .sheet(isPresented: $recordingVM.showRecordingSheet)
        .sheet(isPresented: $showFindBackingTrack) {
            FindBackingTrackSheet(song: song)
        }
    }

    func deleteSong(_ song: Song) {
        for lesson in song.lessons {
            if let url = URL(string: lesson.audioFileURL) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        modelContext.delete(song)
        try? modelContext.save()
    }
}

// MARK: - Inline Recorder View (Bug 5)

struct InlineRecorderView: View {
    let song: Song
    @ObservedObject var recordingVM: RecordingViewModel
    @Binding var selectedType: RecordingType
    let onClose: () -> Void

    // Local timer using view-side pattern (per lessons-learned lesson 13)
    @State private var elapsedSeconds: Double = 0
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var buttonBreathScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 16) {
            if !recordingVM.isRecording {
                // Segmented picker for recording type
                Picker("Recording Type", selection: $selectedType) {
                    Text("🎓 Lesson").tag(RecordingType.lesson)
                    Text("🎤 Performance").tag(RecordingType.performance)
                }
                .pickerStyle(.segmented)

                Text(selectedType == .performance
                     ? "Performances are saved but not transcribed"
                     : "Lesson recordings are transcribed and used to recommend exercises")
                    .font(.system(size: 12))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: selectedType)
            }

            if recordingVM.isRecording {
                // Waveform
                WaveformView(samples: recordingVM.waveformSamples)
                    .frame(height: 50)

                // Timer
                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 28, weight: .light, design: .monospaced))
                    .foregroundColor(SingCoachTheme.textPrimary)
                    .contentTransition(.numericText())
            }

            // Record / Stop button
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(
                            recordingVM.isRecording
                                ? SingCoachTheme.destructive.opacity(0.5)
                                : SingCoachTheme.accent.opacity(0.3),
                            lineWidth: 2
                        )
                        .frame(width: 72, height: 72)

                    Button {
                        if recordingVM.isRecording {
                            stopRecordingAndTimer()
                        } else {
                            startRecordingAndTimer()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(recordingVM.isRecording
                                      ? AnyShapeStyle(SingCoachTheme.destructive)
                                      : AnyShapeStyle(SingCoachTheme.primaryGradient))
                                .frame(width: 56, height: 56)
                                .scaleEffect(recordingVM.isRecording ? buttonBreathScale : 1.0)

                            if recordingVM.isRecording {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white)
                                    .frame(width: 22, height: 22)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(SingCoachTheme.accent)
                            }
                        }
                    }
                }
                .onChange(of: recordingVM.isRecording) { _, isRecording in
                    if isRecording {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            buttonBreathScale = 1.03
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            buttonBreathScale = 1.0
                        }
                    }
                }

                if !recordingVM.isRecording {
                    Text(selectedType == .performance ? "Tap to record performance" : "Tap to record lesson")
                        .font(.system(size: 14))
                        .foregroundColor(SingCoachTheme.textSecondary)
                }

                Spacer()

                if !recordingVM.isRecording {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }
                }
            }

            if recordingVM.transcriptionStatus == .processing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.system(size: 14))
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(SingCoachTheme.surface)
        .cornerRadius(16)
    }

    private func startRecordingAndTimer() {
        elapsedSeconds = 0
        recordingVM.startRecording(recordingType: selectedType.rawValue.lowercased())
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if recordingVM.isRecording {
                    elapsedSeconds += 0.5
                }
            }
    }

    private func stopRecordingAndTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        Task {
            await recordingVM.stopRecording()
            // Auto-close after stopping
            onClose()
        }
    }

    func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Song Header (Bug 4: reflects recording state; Bug 7: cached image)

struct SongHeaderView: View {
    let song: Song
    let onRecord: () -> Void
    @Binding var showFindBackingTrack: Bool
    // Bug 4 fix: observe recordingVM so button updates during recording
    @ObservedObject var recordingVM: RecordingViewModel
    @ObservedObject private var musicKit = MusicKitService.shared
    // Bug 7 fix: cached image loader
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        VStack(spacing: 14) {
            // Artwork — Bug 7 fix: use ImageLoader with URLCache
            Group {
                if let img = imageLoader.image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                } else {
                    artworkPlaceholder
                }
            }
            .onAppear {
                if let artworkURL = song.artworkURL {
                    imageLoader.load(urlString: artworkURL)
                }
            }

            // Title + artist
            VStack(spacing: 4) {
                Text(song.title)
                    .font(SingCoachTheme.headerFont())
                    .foregroundColor(SingCoachTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(song.artist)
                    .font(.system(size: 15))
                    .foregroundColor(SingCoachTheme.textSecondary)
            }

            // Bug 4 fix: Record Lesson button reflects recording state
            Button(action: onRecord) {
                HStack {
                    if recordingVM.isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Recording...")
                    } else {
                        Image(systemName: "mic.fill")
                        Text("Record Lesson")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(recordingVM.isRecording ? Color.red.opacity(0.2) : SingCoachTheme.accent)
                .foregroundColor(recordingVM.isRecording ? Color.red : .black)
                .cornerRadius(14)
            }

            // Karaoke player / link button
            karaokeSection
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
    }

    // MARK: - Karaoke section

    @ViewBuilder
    var karaokeSection: some View {
        if let trackID = song.karaokeTrackID {
            KaraokePlayerCard(
                song: song,
                trackID: trackID,
                onChangeTap: { showFindBackingTrack = true }
            )
        } else {
            Button { showFindBackingTrack = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13))
                    Text("Find Backing Track")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(SingCoachTheme.surface)
                .foregroundColor(SingCoachTheme.textSecondary)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SingCoachTheme.accent.opacity(0.25), lineWidth: 1))
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && t > 0 else { return "0:00" }
        let m = Int(t) / 60; let s = Int(t) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SingCoachTheme.primaryGradient)
                .frame(width: 100, height: 100)
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(SingCoachTheme.accent)
        }
    }
}

// MARK: - Karaoke Player Card

struct KaraokePlayerCard: View {
    let song: Song
    let trackID: String
    let onChangeTap: () -> Void

    @ObservedObject private var musicKit = MusicKitService.shared
    @State private var localSeekFraction: Double = 0
    @State private var isDragging = false

    private var isThisTrack: Bool { musicKit.currentTrackID == trackID }
    private var fraction: Double {
        guard !isDragging else { return localSeekFraction }
        guard isThisTrack && musicKit.trackDuration > 0 else { return 0 }
        return musicKit.playbackTime / musicKit.trackDuration
    }

    var body: some View {
        VStack(spacing: 0) {
            // Track name
            if let title = song.karaokeTrackTitle {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .padding(.bottom, 10)
            }

            // Seek bar + timestamps
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { fraction },
                    set: { v in localSeekFraction = v; isDragging = true }
                ), in: 0...1, onEditingChanged: { editing in
                    if !editing {
                        musicKit.seek(to: localSeekFraction * max(1, musicKit.trackDuration))
                        isDragging = false
                    }
                })
                .tint(.white)

                HStack {
                    Text(formatTime(isDragging ? localSeekFraction * musicKit.trackDuration : (isThisTrack ? musicKit.playbackTime : 0)))
                    Spacer()
                    Text(formatTime(isThisTrack ? musicKit.trackDuration : 0))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            }
            .padding(.bottom, 14)

            // Controls row
            ZStack {
                HStack(spacing: 0) {
                    Spacer()
                    Button { musicKit.skipBackward() } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 52, height: 52)
                    }
                    Spacer()
                    Button {
                        Task {
                            let musicID = MusicItemID(rawValue: trackID)
                            let req = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: musicID)
                            if let result = try? await req.response().items.first {
                                try? await musicKit.togglePlayback(song: result)
                            }
                        }
                    } label: {
                        Image(systemName: (musicKit.isPlaying && isThisTrack) ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 56, height: 56)
                            .background(.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    }
                    Spacer()
                    Button { musicKit.skipForward() } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 52, height: 52)
                    }
                    Spacer()
                }

                HStack {
                    Spacer()
                    Button { onChangeTap() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && t > 0 else { return "0:00" }
        return "\(Int(t)/60):\(String(format: "%02d", Int(t)%60))"
    }
}

// MARK: - Section Tab Bar

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

// MARK: - Lessons Section

struct LessonsSection: View {
    let song: Song
    @ObservedObject var recordingVM: RecordingViewModel
    @Environment(\.modelContext) private var modelContext

    var lessons: [Lesson] {
        song.lessons.filter { !$0.isPerformance }.sorted { $0.date > $1.date }
    }

    var performances: [Lesson] {
        song.lessons.filter { $0.isPerformance }.sorted { $0.date > $1.date }
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
                if !lessons.isEmpty {
                    Text("Lessons")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SingCoachTheme.accent)
                        .padding(.horizontal, 16)

                    ForEach(lessons) { lesson in
                        LessonRowView(lesson: lesson)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteLesson(lesson)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .padding(.horizontal, 16)
                    }
                }

                if !performances.isEmpty {
                    Text("Performances")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#8B5CF6"))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(performances) { lesson in
                        LessonRowView(lesson: lesson)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteLesson(lesson)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    func deleteLesson(_ lesson: Lesson) {
        if let url = URL(string: lesson.audioFileURL) {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(lesson)
        try? modelContext.save()
    }
}

// MARK: - Lesson Row (Bug 2: seek on release; Bug 8: guard nil player)

struct LessonRowView: View {
    let lesson: Lesson
    @StateObject private var player = AudioPlaybackService()
    @State private var showDetail = false
    // Bug 2 fix: seek only on drag release
    @State private var isDragging = false
    @State private var localSeek: Double = 0
    // Bug 8 fix: show load error
    @State private var showLoadError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(lesson.date, style: .date)
                        Text("·")
                        Text(lesson.date, style: .time)
                    }
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

                        if lesson.isPerformance {
                            Text("🎤 Performance")
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "#8B5CF6").opacity(0.2))
                                .foregroundColor(Color(hex: "#8B5CF6"))
                                .cornerRadius(4)
                        }

                        if showLoadError {
                            Text("File not found")
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
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
                            // Bug 8 fix: handle load errors gracefully
                            do {
                                try player.load(url: url)
                                showLoadError = false
                                player.play()
                            } catch {
                                showLoadError = true
                                print("[SingCoach] LessonRowView: failed to load audio: \(error)")
                            }
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
                    // Bug 2 fix: seek only on drag release
                    Slider(value: Binding(
                        get: { isDragging ? localSeek : player.currentTime },
                        set: { localSeek = $0; isDragging = true }
                    ), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                        if !editing {
                            player.seek(to: localSeek)
                            isDragging = false
                        }
                    })
                    .tint(SingCoachTheme.accent)

                    HStack {
                        Text(formatDuration(isDragging ? localSeek : player.currentTime))
                        Spacer()
                        Text(formatDuration(player.duration))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
        .padding(14)
        .background(SingCoachTheme.surface)
        .cornerRadius(12)
        .onTapGesture {
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            LessonDetailSheet(lesson: lesson)
        }
    }

    func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Lesson Detail Sheet (Bug 2: seek on release; Bug 8: guard nil player)

struct LessonDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson
    @StateObject private var player = AudioPlaybackService()
    @State private var speed: Float = 1.0
    // Bug 2 fix: seek only on drag release
    @State private var isDragging = false
    @State private var localSeek: Double = 0
    // Bug 8 fix: show load error
    @State private var showLoadError = false

    let speeds: [Float] = [0.75, 1.0, 1.25, 1.5]

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(lesson.date, style: .date)
                                Text("·")
                                Text(lesson.date, style: .time)
                            }
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(SingCoachTheme.textPrimary)

                            Text(formatDuration(lesson.durationSeconds))
                                .font(.system(size: 15))
                                .foregroundColor(SingCoachTheme.textSecondary)

                            if lesson.isPerformance {
                                Text("🎤 Performance")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "#8B5CF6").opacity(0.2))
                                    .foregroundColor(Color(hex: "#8B5CF6"))
                                    .cornerRadius(8)
                            }

                            if showLoadError {
                                Text("⚠️ Audio file not found")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 12) {
                            // Bug 2 fix: seek only on drag release
                            Slider(value: Binding(
                                get: { isDragging ? localSeek : player.currentTime },
                                set: { localSeek = $0; isDragging = true }
                            ), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                                if !editing {
                                    player.seek(to: localSeek)
                                    isDragging = false
                                }
                            })
                            .tint(SingCoachTheme.accent)

                            HStack {
                                Text(formatDuration(isDragging ? localSeek : player.currentTime))
                                Spacer()
                                Text(formatDuration(player.duration))
                            }
                            .font(.system(size: 12))
                            .foregroundColor(SingCoachTheme.textSecondary)

                            HStack(spacing: 20) {
                                Button {
                                    player.seek(to: max(0, player.currentTime - 15))
                                } label: {
                                    Image(systemName: "gobackward.15")
                                        .font(.system(size: 24))
                                        .foregroundColor(SingCoachTheme.textPrimary)
                                }

                                Button {
                                    if player.isPlaying {
                                        player.pause()
                                    } else {
                                        if let url = URL(string: lesson.audioFileURL) {
                                            if player.duration == 0 {
                                                // Bug 8 fix: handle load errors gracefully
                                                do {
                                                    try player.load(url: url)
                                                    showLoadError = false
                                                } catch {
                                                    showLoadError = true
                                                    print("[SingCoach] LessonDetailSheet: failed to load audio: \(error)")
                                                    return
                                                }
                                            }
                                            player.play()
                                        }
                                    }
                                } label: {
                                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(SingCoachTheme.accent)
                                }

                                Button {
                                    player.seek(to: min(player.duration, player.currentTime + 15))
                                } label: {
                                    Image(systemName: "goforward.15")
                                        .font(.system(size: 24))
                                        .foregroundColor(SingCoachTheme.textPrimary)
                                }
                            }

                            HStack(spacing: 8) {
                                ForEach(speeds, id: \.self) { s in
                                    Button {
                                        speed = s
                                        player.playbackRate = s
                                    } label: {
                                        Text("\(s, specifier: s == 1.0 ? "%.0f" : "%.2g")x")
                                            .font(.system(size: 13, weight: speed == s ? .bold : .regular))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(speed == s ? SingCoachTheme.accent.opacity(0.3) : SingCoachTheme.surface)
                                            .foregroundColor(speed == s ? SingCoachTheme.accent : SingCoachTheme.textSecondary)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(SingCoachTheme.surface)
                        .cornerRadius(16)
                        .padding(.horizontal, 16)

                        if let transcript = lesson.transcript, !transcript.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Transcript")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(SingCoachTheme.accent)

                                Text(transcript)
                                    .font(.system(size: 15))
                                    .foregroundColor(SingCoachTheme.textSecondary)
                                    .lineSpacing(6)
                            }
                            .padding(16)
                            .background(SingCoachTheme.surface)
                            .cornerRadius(16)
                            .padding(.horizontal, 16)
                        }

                        if !lesson.recommendedExercises.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recommended Exercises")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(SingCoachTheme.accent)
                                    .padding(.horizontal, 16)

                                ForEach(lesson.recommendedExercises) { exercise in
                                    ExerciseRowView(exercise: exercise)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Lesson Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SingCoachTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let url = URL(string: lesson.audioFileURL) {
                // Bug 8 fix: handle load errors gracefully on appear
                do {
                    try player.load(url: url)
                } catch {
                    showLoadError = true
                    print("[SingCoach] LessonDetailSheet onAppear: failed to load: \(error)")
                }
            }
        }
    }

    func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Exercises Section

struct ExercisesSection: View {
    let song: Song
    @Environment(\.modelContext) private var modelContext
    @Query private var libraryExercises: [Exercise]
    @State private var showAddExercise = false
    @State private var showExerciseLibrary = false

    init(song: Song) {
        self.song = song
        _libraryExercises = Query(
            filter: #Predicate<Exercise> { $0.templateID != nil && $0.songID == nil },
            sort: \Exercise.name
        )
    }

    var songExercises: [Exercise] {
        song.exercises.sorted { $0.name < $1.name }
    }

    var recommendedExercises: [Exercise] {
        song.mostRecentLesson?.recommendedExercises ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Exercises")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textPrimary)
                Spacer()
                Button {
                    showExerciseLibrary = true
                } label: {
                    Text("Browse Library")
                        .font(.system(size: 12))
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
                Button {
                    showAddExercise = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(SingCoachTheme.accent)
                }
            }
            .padding(.horizontal, 16)

            if songExercises.isEmpty && recommendedExercises.isEmpty {
                EmptyStateView(
                    icon: "figure.mixed.cardio",
                    title: "No Exercises Yet",
                    subtitle: "Record a lesson to get recommendations, or add your own"
                )
                .padding(.top, 40)
            } else {
                if !recommendedExercises.isEmpty {
                    Text("Recommended")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SingCoachTheme.accent)
                        .padding(.horizontal, 16)

                    ForEach(recommendedExercises) { exercise in
                        ExerciseRowView(exercise: exercise)
                            .padding(.horizontal, 16)
                    }
                }

                if !songExercises.isEmpty {
                    Text("Your Exercises")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SingCoachTheme.accent)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    ForEach(songExercises) { exercise in
                        ExerciseRowView(exercise: exercise)
                            .padding(.horizontal, 16)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if exercise.isUserCreated {
                                    Button(role: .destructive) {
                                        deleteExercise(exercise)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(song: song, libraryExercises: libraryExercises)
        }
        .sheet(isPresented: $showExerciseLibrary) {
            ExerciseLibrarySheet(song: song, libraryExercises: libraryExercises)
        }
    }

    func deleteExercise(_ exercise: Exercise) {
        song.exercises.removeAll { $0.id == exercise.id }
        modelContext.delete(exercise)
        try? modelContext.save()
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let song: Song
    let libraryExercises: [Exercise]

    @State private var name = ""
    @State private var selectedCategory: ExerciseCategory = .warmup
    @State private var description = ""

    var suggestions: [Exercise] {
        var seen = Set<String>()
        return libraryExercises
            .sorted { a, b in
                let aNew = !seen.contains(a.category)
                let bNew = !seen.contains(b.category)
                if aNew != bNew { return aNew }
                return a.name < b.name
            }
            .filter { ex in
                let isNew = !seen.contains(ex.category)
                if isNew { seen.insert(ex.category) }
                return true
            }
            .prefix(5)
            .map { $0 }
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Suggestions")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(SingCoachTheme.accent)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(suggestions) { ex in
                                            Button {
                                                name = ex.name
                                                description = ex.exerciseDescription
                                                selectedCategory = ExerciseCategory(rawValue: ex.category) ?? .warmup
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(ex.name)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(SingCoachTheme.textPrimary)
                                                        .lineLimit(1)
                                                    Text(ex.category.capitalized)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(SingCoachTheme.accent)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(SingCoachTheme.surface)
                                                .cornerRadius(10)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(SingCoachTheme.accent.opacity(0.3), lineWidth: 1)
                                                )
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                            .padding(14)
                            .background(SingCoachTheme.surface)
                            .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(SingCoachTheme.textSecondary)
                            TextField("e.g. Lip Trill Scales", text: $name)
                                .padding(12)
                                .background(SingCoachTheme.surface)
                                .cornerRadius(10)
                                .foregroundColor(SingCoachTheme.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Category")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(SingCoachTheme.textSecondary)
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(ExerciseCategory.allCases, id: \.self) { cat in
                                    Text(cat.displayName).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(12)
                            .background(SingCoachTheme.surface)
                            .cornerRadius(10)
                            .foregroundColor(SingCoachTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description (optional)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(SingCoachTheme.textSecondary)
                            TextEditor(text: $description)
                                .frame(minHeight: 80)
                                .padding(8)
                                .background(SingCoachTheme.surface)
                                .cornerRadius(10)
                                .foregroundColor(SingCoachTheme.textPrimary)
                                .scrollContentBackground(.hidden)
                        }

                        Button {
                            saveExercise()
                        } label: {
                            Text("Add Exercise")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(canSave ? SingCoachTheme.accent : SingCoachTheme.textSecondary)
                                .foregroundColor(.black)
                                .cornerRadius(14)
                        }
                        .disabled(!canSave)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    func saveExercise() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            category: selectedCategory.rawValue,
            exerciseDescription: description.isEmpty ? "Custom exercise" : description,
            instruction: "Practice this exercise as needed.",
            focusArea: selectedCategory.displayName,
            isUserCreated: true,
            songID: song.id
        )
        modelContext.insert(exercise)
        song.exercises.append(exercise)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Exercise Library Sheet

struct ExerciseLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let song: Song
    let libraryExercises: [Exercise]

    @State private var selectedCategory: ExerciseCategory? = nil

    var filteredExercises: [Exercise] {
        if let cat = selectedCategory {
            return libraryExercises.filter { $0.category == cat.rawValue }
        }
        return libraryExercises
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                selectedCategory = nil
                            } label: {
                                Text("All")
                                    .font(.system(size: 13, weight: selectedCategory == nil ? .bold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == nil ? SingCoachTheme.accent.opacity(0.3) : SingCoachTheme.surface)
                                    .foregroundColor(selectedCategory == nil ? SingCoachTheme.accent : SingCoachTheme.textSecondary)
                                    .cornerRadius(8)
                            }

                            ForEach(ExerciseCategory.allCases, id: \.self) { cat in
                                Button {
                                    selectedCategory = cat
                                } label: {
                                    Text(cat.displayName)
                                        .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .regular))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedCategory == cat ? SingCoachTheme.accent.opacity(0.3) : SingCoachTheme.surface)
                                        .foregroundColor(selectedCategory == cat ? SingCoachTheme.accent : SingCoachTheme.textSecondary)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredExercises) { exercise in
                                HStack {
                                    ExerciseRowView(exercise: exercise)
                                    Button {
                                        addToSong(exercise)
                                    } label: {
                                        Image(systemName: isAlreadyAdded(exercise) ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.system(size: 24))
                                            .foregroundColor(isAlreadyAdded(exercise) ? .green : SingCoachTheme.accent)
                                    }
                                    .disabled(isAlreadyAdded(exercise))
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SingCoachTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    func isAlreadyAdded(_ exercise: Exercise) -> Bool {
        song.exercises.contains { $0.templateID == exercise.templateID }
    }

    func addToSong(_ exercise: Exercise) {
        guard !isAlreadyAdded(exercise) else { return }
        let copy = Exercise(
            templateID: exercise.templateID,
            name: exercise.name,
            category: exercise.category,
            exerciseDescription: exercise.exerciseDescription,
            instruction: exercise.instruction,
            focusArea: exercise.focusArea,
            youtubeURL: exercise.youtubeURL,
            durationMinutes: exercise.durationMinutes,
            difficulty: exercise.difficulty,
            tips: exercise.tips,
            keywords: exercise.keywords,
            isUserCreated: false,
            songID: song.id
        )
        modelContext.insert(copy)
        song.exercises.append(copy)
        try? modelContext.save()
    }
}
