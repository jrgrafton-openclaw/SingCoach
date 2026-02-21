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

struct GlobalRecordingBanner: View {
    @ObservedObject var recordingVM: RecordingViewModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("Recording...")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text(formatDuration(recordingVM.recordingDuration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Button {
                Task { await recordingVM.stopRecording() }
            } label: {
                Text("Stop")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.1).opacity(0.95))
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.top, 50) // safe area
    }

    func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
