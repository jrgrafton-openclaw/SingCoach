# SingCoach

iOS vocal coaching app — AI-powered singing analysis, real-time pitch detection, tone generation, lyrics display, and practice tracking.

## Stack

- **UI:** SwiftUI (Swift 6 strict concurrency)
- **Data:** SwiftData (no Core Data)
- **Audio:** AVFoundation — `PitchDetectionService` (mic input tap), `ToneGeneratorService` (sine wave via `AVAudioSourceNode`), `AudioRecordingService`, `AudioPlaybackService`
- **AI:** Firebase AI Logic → Vertex AI (Gemini). Two-step: Flash transcribes → Pro analyses. Use `location: "global"` for Gemini 3.x models (default `us-central1` returns 404).
- **Music:** MusicKit (entitlement pending) + Apple Music REST API fallback for artwork
- **Lyrics:** LRCLIB API (synced LRC + plain text)
- **Analytics:** Firebase Analytics + Crashlytics
- **Build:** XcodeGen (`project.yml`) + Fastlane (`bundle exec fastlane beta`)

## Project Structure

```
SingCoach/
  Models/         Song, Lesson, Exercise, PracticeEntry, PracticeSession, LyricsLine
  Services/       PitchDetection, ToneGenerator, AudioPlayback, AudioRecording,
                  GeminiAnalysis, MusicKit, AppleMusic, LRCLib, ExerciseSeeder, Analytics
  Utilities/      AudioCallbacks.swift ← CRITICAL (see below)
  ViewModels/     Per-screen view models
  Views/          SwiftUI views
  Theme/          Colors, typography tokens
SingCoachTests/   74 unit tests + integration test plan (SingCoach.xctestplan)
```

## Build & Ship

```bash
# Always ship via Fastlane — never xcodebuild/altool directly
cd projects/SingCoach
bundle exec fastlane beta
```

- `SKIP_CRASHLYTICS_DSYM_UPLOAD=1` is set in the Fastfile to prevent xcodebuild hangs
- Build numbers are managed via PlistBuddy in Info.plist (not pbxproj)
- Check `git log --oneline -3` and `ls build/*.ipa` before re-running after a failed build

## ⚠️ Critical: Audio Callback Isolation (Swift 6)

**Never define a closure that runs on an audio thread inside a `@MainActor` method.**

The Swift 6 compiler inherits `@MainActor` isolation into the compiler-generated thunk based on the **lexical scope** where a closure is defined — regardless of what it captures. When the thunk runs on a non-main thread (audio tap, render block), the runtime calls `_swift_task_checkIsolatedSwift` → `EXC_BREAKPOINT` crash.

**The fix:** `AudioCallbacks.swift` contains `nonisolated` free functions that *return* the closures:
- `makeAudioTapHandler()` → tap closure for `PitchDetectionService`
- `makeSineRenderBlock()` → render block for `ToneGeneratorService`

**Do NOT:**
- Define audio closures inline in `@MainActor` methods (even with `[weak self]`, `Unmanaged`, or wrapper types — the thunk annotation is the problem, not the captures)
- Use `Task { @MainActor }` from audio threads or Timer callbacks
- Use `.gesture(DragGesture(minimumDistance: 0))` — use `.simultaneousGesture()` instead

**See:** `docs/ios/lessons-learned.md` §57-58 in the workspace for the full pattern and history.

## Known Gotchas

- **Gemini 3.x models** require `.vertexAI(location: "global")` — default `us-central1` gives "FirebaseAiGenerateContent error 0"
- **SwiftData models** must not cross actor boundaries — extract primitives before `Task` boundaries
- **MusicKit entitlement** not yet in provisioning profile — needs manual enable at developer.apple.com
- **Apple Music JWT** expires ~2026-08-19 (key `7UKLD4C2CC`, team `B5X96QDRF4`)
- **YouTube embeds** use `youtube-nocookie.com` + `origin=` param + `referrerpolicy` to avoid error 152
- **Silent mode:** `AudioPlaybackService` sets `.playback` category (not default `.soloAmbient`)
- **Lyrics parsing:** `"¶"` sentinel marks paragraph breaks in LRC/plain text

## Tests

```bash
# Unit tests (74 tests, every build)
xcodebuild test -scheme SingCoach -destination 'platform=iOS Simulator,name=iPhone 16'

# Integration tests (real Firebase + YouTube, on demand)
xcodebuild test -scheme SingCoach -destination '...' -testPlan SingCoach
```

## IDs

- **ASC App:** `6759441600`
- **Bundle:** `com.jrgrafton.singcoach`
- **Firebase Project:** `lobsterproject`
- **TestFlight Beta Group:** `7b26e051-1109-4403-b4a3-86873cbf970e`
