import SwiftUI
import SwiftData

struct ContentView: View {
    // Bug 6 fix: shared RecordingViewModel from environment
    @EnvironmentObject var recordingVM: RecordingViewModel

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                SongsListView()
                    .tabItem {
                        Label("Songs", systemImage: "music.note.list")
                    }

                PracticeView()
                    .tabItem {
                        Label("Practice", systemImage: "flame.fill")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .tint(SingCoachTheme.accent)

            // Bug 6 fix: global recording banner when navigating away while recording
            if recordingVM.isRecording {
                GlobalRecordingBanner(recordingVM: recordingVM)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recordingVM.isRecording)
    }
}

// MARK: - Global Recording Banner
// Shown when user navigates away while recording. Color-coded by type.
// Stop is handled by the FAB on SongDetailView — banner is informational only.

struct GlobalRecordingBanner: View {
    @ObservedObject var recordingVM: RecordingViewModel

    private var isPerformance: Bool { recordingVM.currentRecordingType == "performance" }
    private var accentColor: Color { isPerformance ? Color(hex: "#8B5CF6") : Color(hex: "#F5A623") }
    private var label: String { isPerformance ? "Performance" : "Lesson" }

    var body: some View {
        HStack(spacing: 10) {
            // Pulsing dot
            Circle()
                .fill(accentColor)
                .frame(width: 7, height: 7)

            Text("● \(label)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accentColor)

            Text(formatDuration(recordingVM.recordingDuration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))

            Spacer()

            // Stop — only shown when navigated away (banner is visible)
            Button {
                Task { await recordingVM.stopRecording() }
            } label: {
                Text("Stop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.15))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color(white: 0.12).opacity(0.96))
                .overlay(Capsule().stroke(accentColor.opacity(0.25), lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .padding(.top, 52)
    }

    private func formatDuration(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
