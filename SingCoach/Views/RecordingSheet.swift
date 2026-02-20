import SwiftUI

struct RecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @ObservedObject var viewModel: RecordingViewModel
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    // Song info
                    VStack(spacing: 6) {
                        Text(song.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(SingCoachTheme.textPrimary)
                        Text(song.artist)
                            .font(.system(size: 15))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }

                    // Waveform / idle animation
                    if viewModel.isRecording {
                        WaveformView(samples: viewModel.recorder.waveformSamples)
                            .frame(height: 60)
                            .padding(.horizontal, 24)

                        Text(formatDuration(viewModel.recorder.durationSeconds))
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .foregroundColor(SingCoachTheme.textPrimary)
                    } else {
                        Text("Tap to start recording")
                            .font(.system(size: 16))
                            .foregroundColor(SingCoachTheme.textSecondary)
                    }

                    // Record button
                    ZStack {
                        if !viewModel.isRecording {
                            // Pulse ring
                            Circle()
                                .stroke(SingCoachTheme.accent.opacity(0.3), lineWidth: 2)
                                .frame(width: 80 * pulseScale + 20, height: 80 * pulseScale + 20)
                                .animation(
                                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                    value: pulseScale
                                )
                        } else {
                            // Recording ring
                            Circle()
                                .stroke(SingCoachTheme.destructive, lineWidth: 3)
                                .frame(width: 100, height: 100)
                        }

                        Button {
                            if viewModel.isRecording {
                                Task { await viewModel.stopRecording() }
                            } else {
                                viewModel.startRecording()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isRecording ? AnyShapeStyle(SingCoachTheme.destructive) : AnyShapeStyle(SingCoachTheme.primaryGradient))
                                    .frame(width: 80, height: 80)

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
                    .onAppear {
                        pulseScale = 1.08
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
            .navigationTitle("Record Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if viewModel.isRecording {
                            let _ = viewModel.recorder.stopRecording()
                        }
                        dismiss()
                    }
                    .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
    }

    func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
