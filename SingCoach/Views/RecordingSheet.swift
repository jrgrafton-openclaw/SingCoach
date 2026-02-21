import SwiftUI
import Combine

struct RecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @ObservedObject var viewModel: RecordingViewModel

    // BUG 1 FIX: Local timer state, independent of the recording service
    @State private var elapsedSeconds: Double = 0
    @State private var timerCancellable: AnyCancellable?

    // FEATURE 1: recording type picker
    @State private var selectedRecordingType: RecordingType = .lesson

    // BUG 10 FIX: subtle breathing scale on button, no ugly pulsing ring
    @State private var buttonBreathScale: CGFloat = 1.0

    enum RecordingType: String, CaseIterable {
        case lesson = "Lesson"
        case performance = "Performance"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // FEATURE 1: Segmented picker at top
                    Picker("Recording Type", selection: $selectedRecordingType) {
                        Text("🎓 Lesson").tag(RecordingType.lesson)
                        Text("🎤 Performance").tag(RecordingType.performance)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                    .disabled(viewModel.isRecording)

                    // Contextual description for selected type
                    Text(selectedRecordingType == .performance
                         ? "Performances are saved but not transcribed"
                         : "Lesson recordings are transcribed and used to recommend exercises")
                        .font(.system(size: 12))
                        .foregroundColor(SingCoachTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .animation(.easeInOut(duration: 0.2), value: selectedRecordingType)

                    // Song info
                    VStack(spacing: 6) {
                        Text(song.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(SingCoachTheme.textPrimary)
                        Text(song.artist)
                            .font(.system(size: 15))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }

                    // Waveform / idle state
                    if viewModel.isRecording {
                        // BUG 2 FIX: Use viewModel.waveformSamples (forwarded via Combine)
                        WaveformView(samples: viewModel.waveformSamples)
                            .frame(height: 60)
                            .padding(.horizontal, 24)

                        // BUG 1 FIX: show local elapsedSeconds, not recorder.durationSeconds
                        Text(formatDuration(elapsedSeconds))
                            .font(.system(size: 36, weight: .light, design: .monospaced))
                            .foregroundColor(SingCoachTheme.textPrimary)
                            .contentTransition(.numericText())
                    } else {
                        Text(selectedRecordingType == .performance ? "Tap to record your performance" : "Tap to start recording")
                            .font(.system(size: 16))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }

                    // Record button — BUG 10 FIX: no expanding ring, subtle breathing scale
                    ZStack {
                        // Static outer ring — always visible, not animated
                        Circle()
                            .stroke(
                                viewModel.isRecording ? SingCoachTheme.destructive.opacity(0.5) : SingCoachTheme.accent.opacity(0.3),
                                lineWidth: 2
                            )
                            .frame(width: 104, height: 104)

                        Button {
                            if viewModel.isRecording {
                                stopRecordingAndTimer()
                            } else {
                                startRecordingAndTimer()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isRecording
                                          ? AnyShapeStyle(SingCoachTheme.destructive)
                                          : AnyShapeStyle(SingCoachTheme.primaryGradient))
                                    .frame(width: 80, height: 80)
                                    // BUG 10 FIX: subtle breathing scale on button itself when recording
                                    .scaleEffect(viewModel.isRecording ? buttonBreathScale : 1.0)

                                if viewModel.isRecording {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(SingCoachTheme.accent)
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.isRecording) { _, isRecording in
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

                    if viewModel.transcriptionStatus == .processing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Transcribing...")
                                .font(.system(size: 14))
                                .foregroundColor(SingCoachTheme.textSecondary)
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle(selectedRecordingType == .performance ? "Record Performance" : "Record Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if viewModel.isRecording {
                            stopRecordingAndTimer()
                        }
                        dismiss()
                    }
                    .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Timer helpers (BUG 1 FIX)

    private func startRecordingAndTimer() {
        elapsedSeconds = 0
        viewModel.startRecording(recordingType: selectedRecordingType.rawValue.lowercased())
        // Tick every 0.5s is enough for a timer display
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if viewModel.isRecording {
                    elapsedSeconds += 0.5
                }
            }
    }

    private func stopRecordingAndTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        Task { await viewModel.stopRecording() }
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

// BUG 2 FIX: Added animation on bars
struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(SingCoachTheme.accent)
                        .frame(
                            width: max(2, geometry.size.width / CGFloat(samples.count) - 3),
                            height: max(4, geometry.size.height * CGFloat(sample))
                        )
                        // BUG 2 FIX: explicit animation so height changes are visible
                        .animation(.linear(duration: 0.05), value: sample)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
