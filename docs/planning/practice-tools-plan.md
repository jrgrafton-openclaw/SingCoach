# Practice Tools Implementation Plan

## Overview
Add a "Practice" sheet to lesson detail that provides:
1. **Timer** - track practice duration
2. **Pitch Reference** - play a target note for reference
3. **Pitch Detector** - real-time pitch detection via microphone

---

## UX Changes to Existing UI

### Current Behavior
- `LessonDetailView` has "Mark as Practiced today" button
- Tapping it: increments practice count for that lesson for today (via `LessonProgress` or similar)
- No timer, no audio tools

### New Behavior
1. **Rename button:** "Mark as Practiced today" → "Practice" (or "Practice Tools")
2. **On tap:** Present `PracticeToolsView` as a sheet (NOT increment count directly)
3. **On "Stop":** Save practice duration → creates `PracticeSession` record
4. **Practice history:** Show total time practiced today somewhere visible (maybe on button or in header)

---

## UI/UX

## UI/UX

### Interaction Flow
1. **LessonDetailView** has "Practice" button → presents `.sheet` with PracticeToolsView
2. **PracticeToolsView** - bottom sheet (iOS `.presentationDetents([.medium, .large])`)
3. User taps "Start Practice" → timer starts, pitch detection activates
4. User taps "Stop" → timer stops, duration saved to practice history

### Visual Design
- Dark theme matching current SingCoach aesthetic
- iOS-native components (iOS 16+ style)
- Bottom sheet with grabber handle
- Inset grouped list style for tool rows
- Sheet uses `.presentationDetents([.medium, .large])` - medium by default, drag to expand

### Screen Layout

See interactive mockup: **https://jrgrafton-openclaw.github.io/SingCoach/**

This is the authoritative UI reference. Key behaviors:
- Bottom sheet with grabber
- Timer (left), Pitch Reference (center), Pitch Detector (right/inline)
- Start/Stop toggles both timer + detection
- Slider only changes target for playback, NOT live detection display

---

## Data Model Changes

### Option A: Extend Lesson (simpler)
```swift
// In Lesson model
@Attribute var totalTimePracticedToday: TimeInterval
@Attribute var lastPracticedDate: Date?
```

### Option B: New PracticeSession model (more robust)
```swift
@Model
class PracticeSession {
    var id: UUID
    var lessonID: UUID
    var startTime: Date
    var duration: TimeInterval // seconds
    var date: Date // calendar day
}
```

**Recommendation:** Option B - cleaner separation, supports historical data

---

## Implementation Steps

### Phase 1: UI Shell
1. **Button rename:** Find "Mark as Practiced today" in `LessonDetailView` → rename to "Practice" with play icon
2. **Sheet presentation:** Add `.sheet(isPresented:)` binding to present `PracticeToolsView`
3. Create `PracticeToolsView` (SwiftUI sheet)
4. Build timer UI + start/stop/reset logic
5. Build pitch reference slider (C2-C5) + label showing selected note + frequency
6. Build pitch detector display (static UI first - note name, cents, gauge)
7. **Migrate existing data:** If there's existing practice count data, decide whether to:
   - Keep it as "sessions count" separate from "time practiced"
   - Or archive/migrate it to new `PracticeSession` model

> **Note:** The old "Mark as Practiced" incremented a counter. New flow tracks duration. These are different metrics - consider keeping both or migrating.

### Phase 2: Audio Features

#### 2.1 Pitch Reference Player
- Generate sine wave at given frequency using `AVAudioEngine`
- Frequency calculation: `f = 440 * 2^((midiNum-69)/12)`
- Support notes C2 to C5 (slider range)
- Play button triggers 1-second tone

#### 2.2 Pitch Detection (hardest part)
Options:
| Approach | Pros | Cons |
|----------|------|------|
| **AVAudioEngine + autocorrelation** | No external deps | Need to implement algorithm |
| **Pitchy library** | Swift, well-tested | Need to add SPM package |
| **ToneDetector (iOS 17+ SoundAnalysis)** | Native, powerful | iOS 17+ only, works with files |
| **Third-party (YIN algorithm port)** | Accurate | Need to find reliable one |

**Recommendation:** Implement **autocorrelation** ourselves (no external dep, ~50 lines of code), or use **Pitchy** SPM package

**Autocorrelation basics:**
1. Capture audio buffer from AVAudioEngine
2. Find the period by comparing signal with lagged version
3. Calculate frequency = sampleRate / period
4. Convert frequency to note + cents

**If using Pitchy (SPM):**
```swift
import Pitchy
let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
try detector.start()
detector.onPitchDetected = { pitch in
    // pitch.frequency, pitch.note (with octave), pitch.cents
}
```

**Pitchy usage:**
```swift
let detector = PitchDetector(sampleRate: 44100, bufferSize: 4096)
detector.startDetecting { pitch in
    // pitch.frequency, pitch.noteName, pitch.cents
}
```

### Phase 3: Integration

1. On "Stop" → create `PracticeSession` with duration
2. Save to SwiftData
3. Update lesson's "practiced today" total
4. Show toast/feedback "Saved!"

### Phase 4: Polish
1. Smooth needle animation (60fps)
2. Haptic feedback on start/stop
3. Handle microphone permissions
4. Background audio handling

---

## File Structure & Changes

### New Files to Create
```
SingCoach/
├── Models/
│   └── PracticeSession.swift (NEW)
├── Views/
│   └── Practice/
│       ├── PracticeToolsView.swift (NEW - main sheet)
│       ├── TimerView.swift (NEW - or inline)
│       ├── PitchReferenceView.swift (NEW - or inline)
│       ├── PitchDetectorView.swift (NEW - or inline)
│       └── PitchGaugeView.swift (NEW - needle visualization)
├── Services/
│   ├── ToneGeneratorService.swift (NEW - sine wave playback)
│   │   ├── play(note:midiNote:)
│   │   └── stop()
│   └── PitchDetectionService.swift (NEW - microphone → pitch)
│       ├── start() async throws
│       ├── stop()
│       └── Pitch struct: { note: String, frequency: Double, cents: Double }
```

### Existing Files to Modify
| File | Changes |
|------|---------|
| `LessonDetailView.swift` | Rename "Mark as Practiced today" → "Practice", add `.sheet` |
| `LessonDetailViewModel.swift` | Add `showPracticeTools: Bool` @Published, remove old practice increment |
| `Info.plist` | Add `NSMicrophoneUsageDescription` |
| `AppDelegate.swift` or `SingCoachApp.swift` | Request mic permission on first use |

> **Tip:** Keep views small - `TimerView`, `PitchReferenceView`, `PitchDetectorView` can be `@ViewBuilder` components in separate files for clarity, or inline if simple.

---

## Dependencies

### Swift Package Manager
1. **Pitchy** - pitch detection
   - URL: https://github.com/trevorsch/Pitchy
   - Or: https://github.com/siteline/swift-intersect (no, wrong)

Alternative: Implement simple autocorrelation algorithm (no external dep)

---

## Testing Checklist

### Phase 1 (UI)
- [ ] "Mark as Practiced today" button renamed to "Practice"
- [ ] Tapping "Practice" opens sheet
- [ ] Sheet has grabber, can be dragged to expand
- [ ] Timer displays 00:00 initially
- [ ] Start button begins timer
- [ ] Stop button stops timer
- [ ] Timer resets on next open (or retains?)

### Phase 2 (Audio)
- [ ] Pitch reference slider selects notes C2-C5
- [ ] Target label shows correct note + frequency (e.g., "A4 (440 Hz)")
- [ ] Play button plays sine wave at correct frequency
- [ ] Pitch detector requests microphone permission
- [ ] When singing, detector shows detected note
- [ ] Cents display shows sharp/flat
- [ ] Gauge needle moves left/right based on cents
- [ ] Green "In Tune" when within ±10 cents

### Phase 3 (Data)
- [ ] Stop creates PracticeSession with duration
- [ ] Session saved to SwiftData
- [ ] Lesson shows "practiced X min today" 
- [ ] Old "practice count" still works or migrated

### Phase 4 (Polish)
- [ ] Needle animation is smooth (60fps)
- [ ] Haptic feedback on start/stop
- [ ] Works with headphones (no feedback loop)
- [ ] Background/foreground handling

---

## Notes

- **Microphone permission**: Add `NSMicrophoneUsageDescription` to Info.plist
- **Background audio**: Configure AVAudioSession category (already done in AudioPlaybackService)
- **iOS 16+**: Use `.sheet(isPresented:)` with `.presentationDetents([.medium, .large])`
- **Audio route changes**: Handle headphone disconnect gracefully
- **Audio feedback loop**: When playing pitch reference + detecting voice, may cause feedback. Solution: 
  - Mute speaker when pitch detector active, OR
  - Use headphones, OR
  - Don't auto-play pitch reference during detection

---

## Risks & Trade-offs

| Risk | Mitigation |
|------|------------|
| Pitch detection is inaccurate | Tune algorithm, use larger buffer, test with real voices |
| Audio feedback loop when playing + detecting | Disable speaker during detection, prompt to use headphones |
| User forgets to stop timer | Auto-save on app background (use `@Environment(\.scenePhase)`) |
| Existing practice data lost | Migrate or keep both old + new metrics |
| iOS audio session conflicts | Properly configure AVAudioSession (already handled in AudioPlaybackService) |