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
    @State private var selectedMidiNote: Int = 53 // Default: F3 (middle of range)
    
    var body: some View {
        VStack(spacing: 0) {
            // Grabber handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)
            
            pitchDetectorSection
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            
            pitchReferenceSection
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            
            bottomControlsSection
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SingCoachTheme.background)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)  // We draw our own grabber
        .onDisappear {
            toneGenerator.stop()
            pitchDetector.stop()
            timerCancellable?.cancel()
        }
    }
    
    // MARK: - Pitch Detector Section
    
    private var pitchDetectorSection: some View {
        VStack(spacing: 10) {
            // Note name - centered in full width
            Text(pitchDetector.currentPitch?.noteName ?? "--")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(pitchDetector.currentPitch?.isInTune == true
                    ? Color(hex: "#32D74B")
                    : SingCoachTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            // Status text - centered below note
            Text(statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SingCoachTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            gaugeView
        }
        .padding(20)
        .background(SingCoachTheme.surface)
        .cornerRadius(16)
    }
    
    private var statusText: String {
        guard let pitch = pitchDetector.currentPitch else { return "Waiting..." }
        if abs(pitch.cents) <= 10 { return "In Tune" }
        let sign = pitch.cents > 0 ? "+" : ""
        return "\(sign)\(Int(pitch.cents)) cents"
    }
    
    private var gaugeView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                
                // Colour gradient (faded)
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#FF453A"), Color(hex: "#32D74B"), Color(hex: "#FF453A")],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                    .opacity(0.3)
                
                // Centre line
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2, height: 14)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Needle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 4, height: 18)
                    .shadow(color: .white.opacity(0.8), radius: 4)
                    .position(x: needlePosition(in: geometry.size.width),
                              y: geometry.size.height / 2)
            }
        }
        .frame(height: 20)
        .opacity(pitchDetector.isDetecting ? 1 : 0.3)
    }
    
    private func needlePosition(in width: CGFloat) -> CGFloat {
        let center = width / 2
        guard let cents = pitchDetector.currentPitch?.cents else { return center }
        let clamped = max(-50, min(50, cents))
        return center + CGFloat(clamped / 50) * center
    }
    
    // MARK: - Pitch Reference Section
    
    private var pitchReferenceSection: some View {
        VStack(spacing: 12) {
            // Row: TARGET label | [spacer] | play button
            // Note name sits in its own centred row below
            HStack {
                Text("Target")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button {
                    toneGenerator.play(midiNote: selectedMidiNote)
                } label: {
                    Image(systemName: toneGenerator.isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.system(size: 14))
                        .foregroundColor(SingCoachTheme.accent)
                        .padding(8)
                        .background(Color(hex: "#F5A623").opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Note name centred on its own line
            Text(ToneGeneratorService.noteName(for: selectedMidiNote))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(SingCoachTheme.accent)
                .frame(maxWidth: .infinity, alignment: .center)
            
            // Slider row
            HStack(spacing: 12) {
                Text("C2")
                    .font(.system(size: 12))
                    .foregroundColor(SingCoachTheme.textSecondary)
                
                Slider(
                    value: Binding(
                        get: { Double(selectedMidiNote - 36) },
                        set: { selectedMidiNote = Int($0) + 36 }
                    ),
                    in: 0...36, step: 1
                )
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
            stopPractice()
        } else {
            startPractice()
        }
    }
    
    private func startPractice() {
        isPracticing = true
        elapsedSeconds = 0
        
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in elapsedSeconds += 0.1 }
        
        // Start pitch detection asynchronously — no crash if permission denied
        Task {
            await pitchDetector.start()
        }
    }
    
    private func stopPractice() {
        isPracticing = false
        timerCancellable?.cancel()
        timerCancellable = nil
        pitchDetector.stop()
        
        if elapsedSeconds > 0 {
            let session = PracticeSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                durationSeconds: elapsedSeconds
            )
            modelContext.insert(session)
            try? modelContext.save()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
