import Foundation
import Speech
import Combine

protocol TranscriptionProtocol: AnyObject {
    func transcribe(audioFileURL: URL) async -> Result<String, Error>
}

@MainActor
final class TranscriptionService: ObservableObject, TranscriptionProtocol {
    @Published var isTranscribing = false

    private let recognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        r?.defaultTaskHint = .dictation
        return r
    }()

    // IMPORTANT: nonisolated is required here.
    //
    // TranscriptionService is @MainActor, which makes every method @MainActor-isolated by
    // default. That means the closure passed to SFSpeechRecognizer.requestAuthorization would
    // also be @MainActor-isolated. However, the OS delivers the requestAuthorization callback
    // on a *background* thread via TCC/XPC — NOT the main thread.
    //
    // On iOS 26 the Swift 6 concurrency runtime enforces actor isolation with a hard
    // dispatch_assert_queue check (_swift_task_checkIsolatedSwift). When the TCC callback
    // arrives on a background thread and tries to execute the @MainActor-isolated closure,
    // that assertion fires → EXC_BREAKPOINT / SIGTRAP crash.
    //
    // Marking this function nonisolated removes the @MainActor isolation from the closure
    // body. CheckedContinuation.resume() is thread-safe and needs no actor isolation, so
    // this is safe. This function deliberately accesses no @MainActor state.
    nonisolated func requestPermission() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }

    func transcribe(audioFileURL: URL) async -> Result<String, Error> {
        guard let recognizer, recognizer.isAvailable else {
            print("[SingCoach] SFSpeechRecognizer not available")
            return .failure(TranscriptionError.recognizerUnavailable)
        }

        // Guard: audio file must exist before handing to SFSpeechURLRecognitionRequest
        // (passing a missing-file URL causes a hard crash, not a graceful error)
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            print("[SingCoach] Transcription: audio file missing at \(audioFileURL.path)")
            return .failure(TranscriptionError.audioFileMissing)
        }

        isTranscribing = true
        defer { isTranscribing = false }

        print("[SingCoach] Transcription started: \(audioFileURL.lastPathComponent)")

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        // Enable partial results so we capture the best available transcript even if the
        // recogniser stops or errors early. Apple's network speech service may cap long
        // audio (e.g. 22-min lessons) — with partial results we return what was recognised
        // rather than nothing. isFinal = true signals the definitive end-of-stream result.
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        // Lesson 27: removed requiresOnDeviceRecognition = true (limits to ~60s)
        // Using network transcription for full-length recordings

        // All recognition state is accessed on DispatchQueue.main (the @MainActor executor),
        // serialising reads/writes to didResume and bestTranscript without any explicit lock.
        // This eliminates the Swift 6 data race that previously caused a double-resume crash:
        //   - recognition callback (SFSpeech background queue) → dispatched to main
        //   - timeout DispatchWorkItem (global queue) → dispatched to main
        // Both arrive on main serially, so there is no TOCTOU race on didResume.
        return await withCheckedContinuation { continuation in
            var didResume = false
            var bestTranscript = ""

            // Safety timeout: prevents a hung continuation if the recognizer goes silent
            let timeoutWork = DispatchWorkItem {
                DispatchQueue.main.async {
                    guard !didResume else { return }
                    didResume = true
                    if !bestTranscript.isEmpty {
                        print("[SingCoach] Transcription: timeout — returning best partial (\(bestTranscript.split(separator: " ").count) words)")
                        continuation.resume(returning: .success(bestTranscript))
                    } else {
                        print("[SingCoach] Transcription: 5-minute timeout, no partial transcript available")
                        continuation.resume(returning: .failure(TranscriptionError.timeout))
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeoutWork)

            recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    if let result {
                        // Always update best partial transcript
                        bestTranscript = result.bestTranscription.formattedString

                        if result.isFinal {
                            guard !didResume else { return }
                            didResume = true
                            timeoutWork.cancel()
                            print("[SingCoach] Transcription done (final): \(bestTranscript.split(separator: " ").count) words")
                            continuation.resume(returning: .success(bestTranscript))
                        }
                    }
                    if let error {
                        guard !didResume else { return }
                        didResume = true
                        timeoutWork.cancel()
                        // Return best partial if available (common for long recordings where the
                        // service stops after ~1 min and emits an error rather than isFinal=true)
                        if !bestTranscript.isEmpty {
                            print("[SingCoach] Transcription: error after partial (\(bestTranscript.split(separator: " ").count) words) — using partial. Error: \(error)")
                            continuation.resume(returning: .success(bestTranscript))
                        } else {
                            print("[SingCoach] Transcription failed (no partial): \(error)")
                            continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied
    case audioFileMissing
    case timeout

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available on this device."
        case .permissionDenied:
            return "Speech recognition permission was denied."
        case .audioFileMissing:
            return "The audio recording file could not be found."
        case .timeout:
            return "Speech recognition timed out."
        }
    }
}
