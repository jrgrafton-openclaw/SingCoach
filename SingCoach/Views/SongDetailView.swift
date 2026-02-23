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
    @EnvironmentObject private var recordingVM: RecordingViewModel
    @State private var selectedTab = 0
    @State private var showDeleteConfirm = false
    @State private var showFindBackingTrack = false

    var body: some View {
        ZStack {
            SingCoachTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header contains artwork, title, karaoke player, and record button
                    SongHeaderView(
                        song: song,
                        recordingVM: recordingVM,
                        showFindBackingTrack: $showFindBackingTrack
                    )

                    SectionTabBar(selectedTab: $selectedTab, tabs: ["Lyrics", "Lessons", "Exercises"])
                        .padding(.top, 16)

                    switch selectedTab {
                    case 0:
                        LyricsView(song: song).padding(.top, 8)
                    case 1:
                        LessonsSection(song: song, recordingVM: recordingVM).padding(.top, 8)
                    case 2:
                        ExercisesSection(song: song).padding(.top, 8)
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
                Button { showDeleteConfirm = true } label: {
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
        .sheet(isPresented: $showFindBackingTrack) {
            FindBackingTrackSheet(song: song)
        }
    }

    func deleteSong(_ song: Song) {
        for lesson in song.lessons {
            let url = AudioPathResolver.resolvedURL(lesson.audioFileURL)
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(song)
        try? modelContext.save()
    }
}

// MARK: - Record FAB
// Tap = Lesson (gold). Long-press = Performance (purple).
// Single stop tap ends the recording — no hunting for a hidden button.

private let kFABHintShownKey = "singcoach_fab_hint_shown"

struct RecordFAB: View {
    @ObservedObject var recordingVM: RecordingViewModel

    // Long-press gesture state
    @State private var isLongPressing = false
    @State private var longPressProgress: CGFloat = 0   // 0 → 1 during hold
    @State private var longPressTimer: Timer?
    private let longPressThreshold: CGFloat = 0.4       // seconds to trigger performance
    /// When the long-press threshold fires and starts a performance recording, the finger is
    /// still physically down. The very next DragGesture.onEnded must NOT stop the recording —
    /// it's just the user releasing after the hold. This flag absorbs that one release.
    @State private var ignoreNextRelease: Bool = false

    // FAB animation
    @State private var fabScale: CGFloat = 1.0
    @State private var breathScale: CGFloat = 1.0

    // One-time discoverability hint
    @State private var showHint = !UserDefaults.standard.bool(forKey: kFABHintShownKey)
    @State private var hintOpacity: Double = 0

    // Colours
    private let lessonColor  = Color(hex: "#F5A623")   // warm gold
    private let performColor = Color(hex: "#8B5CF6")   // purple

    private var isRecording: Bool { recordingVM.isRecording }
    private var isPerf: Bool { recordingVM.currentRecordingType == "performance" }
    private var activeColor: Color { isPerf ? performColor : lessonColor }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Hint label — fades in once, disappears after 3s
            if showHint {
                Text("Hold for Performance")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.18).opacity(0.92))
                    .cornerRadius(8)
                    .opacity(hintOpacity)
                    .offset(x: -72)
            }

            // Long-press arc progress ring
            ZStack {
                if isLongPressing && !isRecording {
                    Circle()
                        .trim(from: 0, to: longPressProgress)
                        .stroke(performColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.02), value: longPressProgress)
                }

                // FAB — DragGesture(minimumDistance:0) gives us both press-start and release
                ZStack {
                    Circle()
                        .fill(fabFill)
                        .frame(width: 60, height: 60)
                        .shadow(color: (isRecording ? activeColor : lessonColor).opacity(0.4),
                                radius: isRecording ? 12 : 6, y: 3)
                        .scaleEffect(fabScale * (isRecording ? breathScale : 1.0))

                    if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                    } else if isLongPressing {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(performColor)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isRecording && !isLongPressing {
                                beginLongPress()
                            }
                        }
                        .onEnded { _ in
                            if isRecording {
                                if ignoreNextRelease {
                                    // Long-press just started performance recording — finger lifted
                                    // naturally after hold. Don't stop; just absorb this release.
                                    ignoreNextRelease = false
                                } else {
                                    stopRecording()
                                }
                            } else if isLongPressing {
                                // Released before threshold → tap = Lesson
                                let wasQuickTap = longPressProgress < 1.0
                                cancelLongPress()
                                if wasQuickTap {
                                    startRecording(type: "lesson")
                                }
                                // If progress == 1, performance already started in timer
                            }
                        }
                )
            }
        }
        .onAppear {
            guard showHint else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.4)) { hintOpacity = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeOut(duration: 0.5)) { hintOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showHint = false
                    UserDefaults.standard.set(true, forKey: kFABHintShownKey)
                }
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                // Breathing pulse while recording
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    breathScale = 1.06
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    breathScale = 1.0
                }
            }
        }
    }

    // MARK: - Fill colour

    private var fabFill: AnyShapeStyle {
        if isRecording {
            return AnyShapeStyle(activeColor)
        }
        if isLongPressing {
            // Smoothly interpolate gold → purple during hold
            let t = Double(longPressProgress)
            return AnyShapeStyle(Color(
                red:   lerp(0.961, 0.545, t),
                green: lerp(0.651, 0.361, t),
                blue:  lerp(0.137, 0.965, t)
            ))
        }
        return AnyShapeStyle(lessonColor)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    // MARK: - Gesture handling

    private func beginLongPress() {
        isLongPressing = true
        longPressProgress = 0
        let step: CGFloat = 0.02 / longPressThreshold
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [self] _ in
            Task { @MainActor [self] in
                longPressProgress += step
                if longPressProgress >= 1.0 {
                    longPressTimer?.invalidate()
                    longPressTimer = nil
                    // Threshold reached — haptic + start performance
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    isLongPressing = false
                    longPressProgress = 0
                    // Finger is still physically down; absorb the imminent onEnded release
                    ignoreNextRelease = true
                    startRecording(type: "performance")
                }
            }
        }
    }

    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        isLongPressing = false
        longPressProgress = 0
    }

    private func startRecording(type: String) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { fabScale = 0.88 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { fabScale = 1.0 }
        }
        recordingVM.startRecording(recordingType: type)
    }

    private func stopRecording() {
        cancelLongPress()
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        Task { await recordingVM.stopRecording() }
    }
}

// MARK: - Header Record Button
// Full-width button in the song header. Tap = Lesson, long-press = Performance.
// Same haptic + color-shift UX as the old FAB, but contextually placed.

struct HeaderRecordButton: View {
    @ObservedObject var recordingVM: RecordingViewModel

    @State private var isLongPressing = false
    @State private var longPressProgress: CGFloat = 0
    @State private var longPressTimer: Timer?
    private let longPressThreshold: CGFloat = 0.4
    /// Absorbs the DragGesture.onEnded that fires immediately after a long-press-triggered
    /// performance recording starts (finger is still down when recording begins).
    @State private var ignoreNextRelease: Bool = false

    @State private var buttonScale: CGFloat = 1.0
    @State private var breathScale: CGFloat = 1.0

    // One-time hint
    @State private var showHint = !UserDefaults.standard.bool(forKey: kFABHintShownKey)
    @State private var hintVisible: Bool = false

    private let lessonColor  = Color(hex: "#F5A623")
    private let performColor = Color(hex: "#8B5CF6")

    private var isRecording: Bool { recordingVM.isRecording }
    private var isPerf: Bool { recordingVM.currentRecordingType == "performance" }
    private var activeColor: Color { isPerf ? performColor : lessonColor }

    private var fillColor: Color {
        if isRecording { return activeColor }
        if isLongPressing {
            let t = Double(longPressProgress)
            return Color(red: lerp(0.961, 0.545, t), green: lerp(0.651, 0.361, t), blue: lerp(0.137, 0.965, t))
        }
        return lessonColor
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Long-press progress bar under the button
                if isLongPressing && !isRecording {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(performColor.opacity(0.5))
                            .frame(width: geo.size.width * longPressProgress)
                            .animation(.linear(duration: 0.02), value: longPressProgress)
                    }
                    .frame(height: 2)
                    .cornerRadius(1)
                    .offset(y: 22)
                }

                // Button face
                HStack(spacing: 8) {
                    if isRecording {
                        // Pulsing stop indicator
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .scaleEffect(breathScale)
                        Text(isPerf ? "Stop Performance" : "Stop Lesson")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    } else if isLongPressing {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Hold for Performance…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                        Text("Record Lesson")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(fillColor)
                .cornerRadius(14)
                .scaleEffect(buttonScale)
                .shadow(color: isRecording ? activeColor.opacity(0.4) : .clear, radius: 8, y: 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isRecording && !isLongPressing { beginLongPress() }
                    }
                    .onEnded { _ in
                        if isRecording {
                            if ignoreNextRelease {
                                ignoreNextRelease = false
                            } else {
                                stopRecording()
                            }
                        } else if isLongPressing {
                            let wasQuickTap = longPressProgress < 1.0
                            cancelLongPress()
                            if wasQuickTap { startRecording(type: "lesson") }
                        }
                    }
            )

            // One-time hint
            if showHint && hintVisible {
                Text("Hold to record as Performance")
                    .font(.system(size: 11))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .transition(.opacity)
            }
        }
        .onAppear {
            guard showHint else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { hintVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation { hintVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showHint = false
                    UserDefaults.standard.set(true, forKey: kFABHintShownKey)
                }
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathScale = 1.05 }
            } else {
                withAnimation(.spring(response: 0.3)) { breathScale = 1.0 }
            }
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func beginLongPress() {
        isLongPressing = true
        longPressProgress = 0
        let step: CGFloat = 0.02 / longPressThreshold
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [self] _ in
            Task { @MainActor [self] in
                longPressProgress += step
                if longPressProgress >= 1.0 {
                    longPressTimer?.invalidate(); longPressTimer = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isLongPressing = false; longPressProgress = 0
                    ignoreNextRelease = true
                    startRecording(type: "performance")
                }
            }
        }
    }

    private func cancelLongPress() {
        longPressTimer?.invalidate(); longPressTimer = nil
        isLongPressing = false; longPressProgress = 0
    }

    private func startRecording(type: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { buttonScale = 0.95 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3)) { buttonScale = 1.0 }
        }
        recordingVM.startRecording(recordingType: type)
    }

    private func stopRecording() {
        cancelLongPress()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await recordingVM.stopRecording() }
    }
}

// MARK: - Song Header (artwork + title + karaoke + inline record button)

struct SongHeaderView: View {
    let song: Song
    @ObservedObject var recordingVM: RecordingViewModel
    @Binding var showFindBackingTrack: Bool
    @ObservedObject private var musicKit = MusicKitService.shared
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        VStack(spacing: 14) {
            // Artwork
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

            // Karaoke player / link button
            karaokeSection

            // Record button — same tap/long-press UX as FAB, but inline in header
            HeaderRecordButton(recordingVM: recordingVM)
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
    // Loading state: true while MusicKit fetches + buffers before first play
    @State private var isLoading = false

    private var isThisTrack: Bool { musicKit.currentTrackID == trackID }
    private var fraction: Double {
        guard !isDragging else { return localSeekFraction }
        guard isThisTrack && musicKit.trackDuration > 0 else { return 0 }
        return musicKit.playbackTime / musicKit.trackDuration
    }

    var body: some View {
        VStack(spacing: 0) {
            if let title = song.karaokeTrackTitle {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .padding(.bottom, 10)
            }

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
                .disabled(isLoading)

                HStack {
                    Text(formatTime(isDragging ? localSeekFraction * musicKit.trackDuration : (isThisTrack ? musicKit.playbackTime : 0)))
                    Spacer()
                    Text(formatTime(isThisTrack ? musicKit.trackDuration : 0))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            }
            .padding(.bottom, 14)

            ZStack {
                HStack(spacing: 0) {
                    Spacer()
                    Button { musicKit.skipBackward() } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.white.opacity(isLoading ? 0.3 : 0.8))
                            .frame(width: 52, height: 52)
                    }
                    .disabled(isLoading)
                    Spacer()

                    // Play/pause button — shows spinner while loading
                    Button {
                        handlePlayTap()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 56, height: 56)
                                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)

                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: (musicKit.isPlaying && isThisTrack) ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .disabled(isLoading)

                    Spacer()
                    Button { musicKit.skipForward() } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.white.opacity(isLoading ? 0.3 : 0.8))
                            .frame(width: 52, height: 52)
                    }
                    .disabled(isLoading)
                    Spacer()
                }
                // Clear loading once MusicKit reports it's actually playing
                .onChange(of: musicKit.isPlaying) { _, playing in
                    if playing && isThisTrack { isLoading = false }
                }
                // Also clear if track changes away (error/cancel)
                .onChange(of: musicKit.currentTrackID) { _, _ in
                    isLoading = false
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

    private func handlePlayTap() {
        if musicKit.isPlaying && isThisTrack {
            // Already playing this track — just pause, no load needed
            musicKit.pause()
        } else if !isThisTrack || (!musicKit.isPlaying && musicKit.currentTrackID == trackID) {
            // Need to fetch + play — show loading immediately
            isLoading = true
            Task {
                let musicID = MusicItemID(rawValue: trackID)
                let req = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: musicID)
                if let result = try? await req.response().items.first {
                    do {
                        try await musicKit.togglePlayback(song: result)
                    } catch {
                        isLoading = false
                        print("[SingCoach] KaraokePlayerCard: playback error: \(error)")
                    }
                } else {
                    isLoading = false
                    print("[SingCoach] KaraokePlayerCard: track not found for ID \(trackID)")
                }
            }
        }
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
    @State private var retranscribingID: UUID? = nil

    var lessons: [Lesson] {
        song.lessons.filter { !$0.isPerformance }.sorted { $0.date > $1.date }
    }

    var performances: [Lesson] {
        song.lessons.filter { $0.isPerformance }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        .padding(.bottom, 8)

                    // List required for swipeActions to work (VStack/ScrollView doesn't support them)
                    List {
                        ForEach(lessons) { lesson in
                            LessonRowView(lesson: lesson, songTitle: song.title)
                                .listRowBackground(SingCoachTheme.surface)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteLesson(lesson)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if !lesson.isPerformance && lesson.status != .processing {
                                        Button {
                                            retranscribe(lesson)
                                        } label: {
                                            Label("Retranscribe", systemImage: "waveform.badge.magnifyingglass")
                                        }
                                        .tint(SingCoachTheme.accent)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if retranscribingID == lesson.id {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .padding(8)
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .frame(minHeight: CGFloat(lessons.count) * 90, maxHeight: CGFloat(lessons.count) * 160)
                    .background(SingCoachTheme.background)
                }

                if !performances.isEmpty {
                    Text("Performances")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#8B5CF6"))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    List {
                        ForEach(performances) { lesson in
                            LessonRowView(lesson: lesson, songTitle: song.title)
                                .listRowBackground(SingCoachTheme.surface)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteLesson(lesson)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .frame(minHeight: CGFloat(performances.count) * 90, maxHeight: CGFloat(performances.count) * 160)
                    .background(SingCoachTheme.background)
                }
            }
        }
    }

    func deleteLesson(_ lesson: Lesson) {
        let url = AudioPathResolver.resolvedURL(lesson.audioFileURL)
        try? FileManager.default.removeItem(at: url)
        song.lessons.removeAll { $0.id == lesson.id }
        modelContext.delete(lesson)
        try? modelContext.save()
    }

    func retranscribe(_ lesson: Lesson) {
        retranscribingID = lesson.id
        let audioURL = AudioPathResolver.resolvedURL(lesson.audioFileURL)
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        Task {
            lesson.transcriptionStatus = TranscriptionStatus.processing.rawValue
            try? modelContext.save()

            let service = TranscriptionService()

            // Ensure permission is granted before starting (Lesson 21: delay avoids silent failure)
            let granted = await service.requestPermission()
            guard granted else {
                lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
                try? modelContext.save()
                retranscribingID = nil
                print("[SingCoach] Re-transcribe: speech permission denied")
                return
            }

            // Small delay after permission dialog to let any UI settle (Lesson 21)
            try? await Task.sleep(nanoseconds: 300_000_000)

            let result = await service.transcribe(audioFileURL: audioURL)
            switch result {
            case .success(let transcript):
                lesson.transcript = transcript
                lesson.transcriptionStatus = TranscriptionStatus.done.rawValue
                let recommender = ExerciseRecommendationService()
                let recommended = await recommender.recommendAsync(
                    transcript: transcript, song: song, allExercises: allExercises)
                lesson.recommendedExercises = recommended
                print("[SingCoach] Re-transcribe done: \(transcript.split(separator: " ").count) words, \(recommended.count) exercises")
            case .failure(let error):
                lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
                print("[SingCoach] Re-transcribe failed: \(error)")
            }
            try? modelContext.save()
            retranscribingID = nil
        }
    }
}

// MARK: - Lesson Row (Bug 2: seek on release; Bug 8: guard nil player)

struct LessonRowView: View {
    let lesson: Lesson
    var songTitle: String = "Recording"
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
                        // Lesson 32: resolve relative or legacy absolute path
                        let url = AudioPathResolver.resolvedURL(lesson.audioFileURL)
                        do {
                            try player.load(url: url)
                            showLoadError = false
                            player.play()
                        } catch {
                            showLoadError = true
                            print("[SingCoach] LessonRowView: failed to load audio: \(error)")
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
            LessonDetailSheet(lesson: lesson, songTitle: songTitle)
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

// MARK: - Custom Slider (small circular thumb)

struct CustomSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumTrackTintColor = UIColor(SingCoachTheme.accent)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.15)
        // Draw a small solid white circle as thumb
        let size: CGFloat = 14
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let thumb = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown),       for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchUp),         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.minimumValue = Float(range.lowerBound)
        uiView.maximumValue = Float(range.upperBound)
        if !context.coordinator.isDragging {
            uiView.value = Float(value)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: CustomSlider
        var isDragging = false
        init(_ parent: CustomSlider) { self.parent = parent }

        @objc func touchDown() {
            isDragging = true
            parent.onEditingChanged(true)
        }
        @objc func valueChanged(_ slider: UISlider) {
            parent.value = Double(slider.value)
        }
        @objc func touchUp() {
            isDragging = false
            parent.onEditingChanged(false)
        }
    }
}

// MARK: - Lesson Detail Sheet (Bug 2: seek on release; Bug 8: guard nil player)

struct LessonDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let lesson: Lesson
    var songTitle: String = "Recording"
    @StateObject private var player = AudioPlaybackService()
    @State private var speed: Float = 1.0
    // Bug 2 fix: seek only on drag release
    @State private var isDragging = false
    @State private var localSeek: Double = 0
    // Bug 8 fix: show load error
    @State private var showLoadError = false
    // Refresh transcript
    @State private var isRetranscribing = false
    @StateObject private var transcriptionService = TranscriptionService()

    let speeds: [Float] = [0.75, 1.0, 1.25, 1.5]

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            // Date · Time — compact format: "Mon, Feb 22 · 7:47 PM"
                            Text(formattedHeaderDate(lesson.date))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(SingCoachTheme.textPrimary)

                            // Duration as subtitle
                            Text(formatDuration(lesson.durationSeconds))
                                .font(.system(size: 13))
                                .foregroundColor(SingCoachTheme.textSecondary)

                            if showLoadError {
                                Text("⚠️ Audio file not found")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 12) {
                            // Custom slider — small circular thumb (Bug 2: seek on release)
                            CustomSlider(
                                value: Binding(
                                    get: { isDragging ? localSeek : player.currentTime },
                                    set: { localSeek = $0 }
                                ),
                                range: 0...max(player.duration, 1),
                                onEditingChanged: { editing in
                                    if editing {
                                        isDragging = true
                                    } else {
                                        player.seek(to: localSeek)
                                        isDragging = false
                                    }
                                }
                            )
                            .frame(height: 28)

                            HStack {
                                Text(formatDuration(isDragging ? localSeek : player.currentTime))
                                Spacer()
                                Text(formatDuration(player.duration))
                            }
                            .font(.system(size: 12))
                            .foregroundColor(SingCoachTheme.textSecondary)

                            // Single transport row: [Speed] ——— [←15 ▶ 15→] ——— [Share]
                            let exportURL = AudioPathResolver.resolvedURL(lesson.audioFileURL)
                            let exportTitle = "\(songTitle) – \(lesson.date.formatted(date: .abbreviated, time: .shortened))"
                            HStack(spacing: 0) {
                                // Speed cycle button — left anchor, equal-width column for true centering
                                Button {
                                    let idx = speeds.firstIndex(of: speed) ?? 1
                                    speed = speeds[(idx + 1) % speeds.count]
                                    player.playbackRate = speed
                                } label: {
                                    Text("\(speed, specifier: speed == 1.0 ? "%.0f" : "%.2g")x")
                                        .font(.system(size: 15, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundColor(SingCoachTheme.textSecondary)
                                        .cornerRadius(10)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Transport controls — centered
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
                                            if player.duration == 0 {
                                                // Lesson 32: resolve relative or legacy absolute path
                                                let url = AudioPathResolver.resolvedURL(lesson.audioFileURL)
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

                                // Share / export — right anchor, equal-width column for true centering
                                ShareLink(
                                    item: exportURL,
                                    preview: SharePreview(exportTitle, image: Image(systemName: "waveform"))
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 17))
                                        .foregroundColor(SingCoachTheme.textSecondary)
                                        .padding(6)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            // Transcribe button — visible for all recordings
                            Divider().background(SingCoachTheme.textSecondary.opacity(0.2))
                            Button { refreshTranscript() } label: {
                                if isRetranscribing {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.8)
                                        Text(transcriptionService.chunkProgress.isEmpty
                                             ? "Transcribing…"
                                             : transcriptionService.chunkProgress)
                                            .font(.system(size: 14))
                                            .foregroundColor(SingCoachTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "waveform.badge.magnifyingglass")
                                            .font(.system(size: 14))
                                        Text(lesson.transcript?.isEmpty == false ? "Re-transcribe" : "Transcribe")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(SingCoachTheme.accent)
                                }
                            }
                            .disabled(isRetranscribing)
                            .padding(.top, 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(SingCoachTheme.surface)
                        .cornerRadius(16)
                        .padding(.horizontal, 16)

                        // Transcript card — visible for any recording that has a transcript
                        if let transcript = lesson.transcript, !transcript.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Transcript")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(SingCoachTheme.accent)
                                TranscriptView(transcript: transcript)
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
            .navigationTitle(lesson.isPerformance ? "Performance Detail" : "Lesson Detail")
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
            // Lesson 32: resolve relative or legacy absolute path
            let url = AudioPathResolver.resolvedURL(lesson.audioFileURL)
            do {
                try player.load(url: url)
            } catch {
                showLoadError = true
                print("[SingCoach] LessonDetailSheet onAppear: failed to load: \(error)")
            }
        }
    }

    func refreshTranscript() {
        guard !isRetranscribing else { return }
        isRetranscribing = true
        let audioURL = AudioPathResolver.resolvedURL(lesson.audioFileURL)
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        Task {
            lesson.transcriptionStatus = TranscriptionStatus.processing.rawValue
            try? modelContext.save()

            let granted = await transcriptionService.requestPermission()
            guard granted else {
                lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
                try? modelContext.save()
                isRetranscribing = false
                return
            }
            // Lesson 21: brief delay after permission dialog
            try? await Task.sleep(nanoseconds: 300_000_000)

            let result = await transcriptionService.transcribe(audioFileURL: audioURL)
            switch result {
            case .success(let transcript):
                lesson.transcript = transcript
                lesson.transcriptionStatus = TranscriptionStatus.done.rawValue
                let allSongs = (try? modelContext.fetch(FetchDescriptor<Song>())) ?? []
                if let song = allSongs.first(where: { $0.id == lesson.songID }) {
                    let recommended = await ExerciseRecommendationService()
                        .recommendAsync(transcript: transcript, song: song, allExercises: allExercises)
                    lesson.recommendedExercises = recommended
                }
                print("[SingCoach] LessonDetailSheet: refreshed transcript (\(transcript.split(separator: " ").count) words)")
            case .failure(let error):
                lesson.transcriptionStatus = TranscriptionStatus.failed.rawValue
                print("[SingCoach] LessonDetailSheet: refresh failed: \(error)")
            }
            try? modelContext.save()
            isRetranscribing = false
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

    func formattedHeaderDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
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

// MARK: - Transcript View

/// Renders a lesson transcript with optional timestamp markers and paragraph breaks.
///
/// Handles two formats:
///   New (chunked):  "[0:00]\ntext...\n\n[0:55]\ntext..." — paragraphs with timestamp badges
///   Legacy (flat):  "plain text without markers"         — single paragraph, no badges
///
/// The max-height ScrollView keeps the card compact on short displays while
/// still exposing the full transcript for long recordings.
struct TranscriptView: View {

    let transcript: String

    struct Segment: Identifiable {
        let id = UUID()
        let timestamp: String?   // e.g. "0:00", nil for legacy flat transcripts
        let text: String
    }

    /// Parse transcript into segments, splitting on double-newlines.
    /// Recognises lines of the form "[M:SS]" or "[MM:SS]" as timestamp markers.
    var segments: [Segment] {
        let blocks = transcript
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return blocks.map { block in
            let lines = block.components(separatedBy: "\n")
            if let firstLine = lines.first,
               firstLine.hasPrefix("["), firstLine.hasSuffix("]") {
                let inner = String(firstLine.dropFirst().dropLast())
                let parts = inner.components(separatedBy: ":")
                if parts.count == 2,
                   parts[0].allSatisfy(\.isNumber),
                   parts[1].count == 2,
                   parts[1].allSatisfy(\.isNumber) {
                    let body = lines.dropFirst()
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return Segment(timestamp: inner, text: body)
                }
            }
            return Segment(timestamp: nil, text: block)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { seg in
                    VStack(alignment: .leading, spacing: 5) {
                        if let ts = seg.timestamp {
                            Text(ts)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(SingCoachTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(SingCoachTheme.accent.opacity(0.15))
                                .cornerRadius(5)
                        }
                        if !seg.text.isEmpty {
                            Text(seg.text)
                                .font(.system(size: 15))
                                .foregroundColor(SingCoachTheme.textSecondary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 280)
    }
}
