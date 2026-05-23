# SingCoach

iOS vocal coaching app — AI-powered singing analysis, real-time pitch detection, tone generation, lyrics display, and practice tracking.

## Stack

- **UI:** SwiftUI (Swift 6 strict concurrency)
- **Data:** SwiftData (no Core Data)
- **Audio:** AVFoundation — `PitchDetectionService` (mic input tap), `ToneGeneratorService` (sine wave via `AVAudioSourceNode`), `AudioRecordingService`, `AudioPlaybackService`
- **AI:** Firebase AI Logic → Vertex AI (Gemini). **Single-call:** Pro 3.1 receives audio + analysis prompt, returns structured JSON with transcript + scores in one request. Pro hears the audio directly (acoustic scoring), no separate Flash transcription pass. Use `location: "global"` for Gemini 3.x models (default `us-central1` returns 404).
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
# Dev install + launch on the connected iPhone (one command, no UI gymnastics)
./scripts/install-on-device.sh

# TestFlight ship — always via Fastlane, never xcodebuild/altool directly
bundle exec fastlane beta
```

- **Project generation:** `.xcodeproj` is generated from `project.yml` via XcodeGen (`brew install xcodegen`). `project.yml` is the source of truth; never hand-edit pbxproj. `scripts/install-on-device.sh` and `lane :beta` both run `xcodegen generate` at start (and `lane :beta` regens at end too) to reset signing to Automatic + Apple Development.
- **Signing dance — why this matters:** `lane :beta` flips pbxproj to manual Apple Distribution signing for the upload. The final `regen_project` step undoes that, so the next dev install (or Xcode Run) works without manually flipping signing back to Automatic. Never commit pbxproj changes from a Fastlane run — `lane :beta` only commits `Info.plist` (build bump).
- **Dev install internals:** `scripts/install-on-device.sh` does `xcodegen generate` → `xcodebuild build` (Debug, `-allowProvisioningUpdates`) → `xcrun devicectl device install app` → `xcrun devicectl device process launch`. Auto-detects the first connected iPhone via `devicectl list devices --json-output`.
- **First-time device registration:** the first dev install on a new device must happen from the Xcode IDE (⌘R) so Xcode can register the device's UDID on App Store Connect via your Apple ID. After that, the CLI script works forever.
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
- **SwiftData models** must not cross actor boundaries — extract primitives before `Task` boundaries. Example: `GeminiAnalysisService.analyze(...)` takes `[AIExerciseSummary]` (Sendable struct), not `[Exercise]` (`@Model`). Pattern: map model array → Sendable summary array on MainActor, then pass the summary across the actor boundary.
- **Vertex error surfacing:** when a Firebase AI call fails with an opaque "error 0" or "error 3", inspect `response.promptFeedback?.blockReason`, `candidate.finishReason`, and unpack `NSError.userInfo` chain. `GeminiAnalysisService.describe(_:)` does this — re-use the pattern for any other Firebase AI integration.
- **MusicKit entitlement** not yet in provisioning profile — needs manual enable at developer.apple.com
- **Apple Music JWT** expires ~2026-08-19 (key `7UKLD4C2CC`, team `B5X96QDRF4`)
- **YouTube embeds** use `youtube-nocookie.com` + `origin=` param + `referrerpolicy` to avoid error 152
- **Silent mode:** `AudioPlaybackService` sets `.playback` category (not default `.soloAmbient`)
- **Lyrics parsing:** `"¶"` sentinel marks paragraph breaks in LRC/plain text

## Tests

```bash
# Unit tests (every build) — use iPhone 17 sim (16 not available locally)
xcodebuild test -scheme SingCoach -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skip-testing:SingCoachTests/GeminiIntegrationTests \
  -skip-testing:SingCoachTests/YouTubeEmbedIntegrationTests

# Integration tests (real Firebase + YouTube, on demand)
xcodebuild test -scheme SingCoach -destination '...' -testPlan SingCoach
```

## Preserving recordings across deploys

TestFlight updates preserve the app sandbox (recordings in `Documents/Lessons/{songID}/` + SwiftData store) **iff**:
- App is updated, not deleted-and-reinstalled
- Bundle ID and team ID unchanged
- No `@Model` schema changes (no `VersionedSchema`/`MigrationPlan` configured → lightweight migration only handles *adding* an optional property; renames/type changes silently fall back to a fresh empty store)

**Safe-deploy checklist for bugfixes:** scope edits to non-`@Model` files. If you must add a field to a `@Model`, make it `Optional` with a default. To grab a granular backup of recordings before a risky change: install a dev build over the TestFlight one (same bundle ID = sandbox preserved), then Xcode → Devices and Simulators → SingCoach → ⚙ → Download Container. Dev builds have `get-task-allow`; TestFlight builds don't, so this only works post-dev-install.

## IDs

- **ASC App:** `6759441600`
- **Bundle:** `com.jrgrafton.singcoach`
- **Firebase Project:** `lobsterproject`
- **TestFlight Beta Group:** `7b26e051-1109-4403-b4a3-86873cbf970e`
