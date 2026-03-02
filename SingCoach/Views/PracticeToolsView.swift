import SwiftUI
import Combine
import SwiftData

struct PracticeToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let exercise: Exercise
    
    @StateObject private var toneGenerator = ToneGeneratorService()
    @StateObject private var pitchDetector = PitchDetectionService()
    
    @State private var isPracticing = false
    @State private var elapsedSeconds: Double = 0
    @State private var timerCancellable: AnyCancellable?
    @State private var selectedMidiNote: Int = 54 // Default: F#3 (actual middle of vocal range)
    
    var body: some View {
        VStack(spacing: 0) {
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
        .presentationDragIndicator(.visible)
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
                .animation(.easeInOut(duration: 0.15), value: pitchDetector.currentPitch?.noteName)
                .contentTransition(.numericText())
            
            // Status text - centered below note
            Text(statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SingCoachTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.15), value: statusText)
            
            gaugeView
        }
        .padding(20)
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
                    .animation(.interpolatingSpring(stiffness: 120, damping: 14), value: pitchDetector.currentPitch?.cents)
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
            // One row: TARGET (left) | F3 centred | speaker (right)
            // Use a 3-column layout — left and right columns are equal width so the
            // centre column is truly centred across the full container.
            HStack(spacing: 0) {
                // Left: TARGET label, left-aligned
                Text("Target")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Centre: note name, always centred
                Text(ToneGeneratorService.noteName(for: selectedMidiNote))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(SingCoachTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // Right: speaker button, right-aligned
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
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
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
        
        guard elapsedSeconds > 0 else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let templateID = exercise.templateID ?? exercise.name
        let exerciseID = exercise.id

        // 1) Upsert PracticeSession — accumulates timer duration for today
        let sessionDescriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.exerciseID == exerciseID && $0.date == today }
        )
        if let existing = (try? modelContext.fetch(sessionDescriptor))?.first {
            existing.durationSeconds += elapsedSeconds
        } else {
            let session = PracticeSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                durationSeconds: elapsedSeconds,
                templateID: templateID
            )
            modelContext.insert(session)
        }

        // 2) Ensure a PracticeEntry exists for today — this is what the history view shows.
        //    Create one if it doesn't exist; if it already exists (e.g. from "Mark as Practiced"),
        //    leave it alone (the duration is read from PracticeSession anyway).
        let entryDescriptor = FetchDescriptor<PracticeEntry>(
            predicate: #Predicate { $0.exerciseTemplateID == templateID && $0.date >= today }
        )
        if (try? modelContext.fetch(entryDescriptor))?.isEmpty != false {
            let entry = PracticeEntry(
                exerciseTemplateID: templateID,
                exerciseName: exercise.name,
                exerciseCategory: exercise.category
            )
            modelContext.insert(entry)
        }

        try? modelContext.save()
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
