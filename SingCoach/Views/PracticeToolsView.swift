import SwiftUI
import Combine

struct PracticeToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let exercise: Exercise
    
    @StateObject private var toneGenerator = ToneGeneratorService()
    @StateObject private var pitchDetector = PitchDetectionService()
    
    @State private var isPracticing = false
    @State private var elapsedSeconds: Double = 0
    @State private var timerCancellable: AnyCancellable?
    @State private var selectedMidiNote: Int = 60 // Default to C4 (MIDI 60)
    
    var body: some View {
        VStack(spacing: 0) {
            // Grabber handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)
            
            // Pitch Detector Section
            pitchDetectorSection
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            
            // Pitch Reference Section
            pitchReferenceSection
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            
            // Bottom Controls
            bottomControlsSection
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            
            Spacer()
        }
        .background(SingCoachTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium])
        .onDisappear {
            toneGenerator.stop()
            Task { await pitchDetector.stop() }
            timerCancellable?.cancel()
        }
    }
    
    // MARK: - Pitch Detector Section
    
    private var pitchDetectorSection: some View {
        VStack(spacing: 12) {
            // Note display - centered
            Text(pitchDetector.currentPitch?.noteName ?? "--")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(pitchDetector.currentPitch?.isInTune == true ? Color(hex: "#32D74B") : SingCoachTheme.textPrimary)
                .fontDesign(.rounded)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            // Status text - below the note, centered
            Text(pitchDetector.currentPitch.map { cents -> String in
                if abs(cents.cents) <= 10 { return "In Tune" }
                let sign = cents.cents > 0 ? "+" : ""
                return "\(sign)\(Int(cents.cents)) cents"
            } ?? "Waiting...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SingCoachTheme.textSecondary)
                .multilineTextAlignment(.center)
            
            gaugeView
        }
        .padding(20)
        .background(SingCoachTheme.surface)
        .cornerRadius(16)
    }
    
    private var gaugeView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                
                // Color gradient (faded)
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color(hex: "#FF453A"), Color(hex: "#32D74B"), Color(hex: "#FF453A")], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                    .opacity(0.3)
                
                // Center line
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2, height: 14)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Needle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 4, height: 18)
                    .shadow(color: .white.opacity(0.8), radius: 4)
                    .position(x: needlePosition(in: geometry.size.width), y: geometry.size.height / 2)
            }
        }
        .frame(height: 20)
        .opacity(pitchDetector.isDetecting ? 1 : 0.3)
    }
    
    private func needlePosition(in width: CGFloat) -> CGFloat {
        let center = width / 2
        guard let cents = pitchDetector.currentPitch?.cents else { return center }
        let clampedCents = max(-50, min(50, cents))
        return center + (clampedCents / 50) * center
    }
    
    // MARK: - Pitch Reference Section
    
    private var pitchReferenceSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Target")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text(ToneGeneratorService.noteName(for: selectedMidiNote))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SingCoachTheme.accent)
                
                Button {
                    Task {
                        toneGenerator.play(midiNote: selectedMidiNote)
                    }
                } label: {
                    Image(systemName: toneGenerator.isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.system(size: 14))
                        .foregroundColor(SingCoachTheme.accent)
                        .padding(8)
                        .background(Color(hex: "#F5A623").opacity(0.15))
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 12) {
                Text("C2")
                    .font(.system(size: 12))
                    .foregroundColor(SingCoachTheme.textSecondary)
                
                Slider(value: Binding(
                    get: { Double(selectedMidiNote - 36) },
                    set: { selectedMidiNote = Int($0) + 36 }
                ), in: 0...36, step: 1)
                .tint(SingCoachTheme.accent)
                
                Text("C5")
                    .font(.system(size: 12))
                    .foregroundColor(SingCoachTheme.textSecondary)
            }
            
            Text("\(Int(ToneGeneratorService.frequency(for: selectedMidiNote))) Hz")
                .font(.system(size: 12))
                .foregroundColor(SingCoachTheme.textSecondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControlsSection: some View {
        HStack(spacing: 12) {
            Text(formatTime(elapsedSeconds))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(SingCoachTheme.textPrimary)
                .frame(width: 70)
                .padding(18)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
            
            Button {
                togglePractice()
            } label: {
                Text(isPracticing ? "Stop" : "Start Practice")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(isPracticing ? Color(hex: "#FF453A") : SingCoachTheme.accent)
                    .foregroundColor(isPracticing ? .white : .black)
                    .cornerRadius(16)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Actions
    
    private func togglePractice() {
        if isPracticing {
            // Stop practicing
            isPracticing = false
            timerCancellable?.cancel()
            timerCancellable = nil
            
            Task {
                await pitchDetector.stop()
            }
            
            // Save practice session
            if elapsedSeconds > 0 {
                let session = PracticeSession(exerciseID: exercise.id, exerciseName: exercise.name, durationSeconds: elapsedSeconds)
                modelContext.insert(session)
                try? modelContext.save()
            }
        } else {
            // Start practicing
            isPracticing = true
            elapsedSeconds = 0
            
            // Start timer
            timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in elapsedSeconds += 0.1 }
            
            // Start pitch detection (safely)
            Task {
                do {
                    try await pitchDetector.start()
                } catch {
                    print("[PracticeTools] Pitch detection failed: \(error.localizedDescription)")
                    // Don't crash - just continue without pitch detection
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
