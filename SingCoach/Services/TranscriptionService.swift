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

    func requestPermission() async -> Bool {
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
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        // Lesson 27: removed requiresOnDeviceRecognition = true (limits to ~60s)
        // Using network transcription for full-length recordings

        // Run recognition task. SFSpeechRecognizer is @MainActor-bound (non-Sendable) so we
        // call recognitionTask directly on @MainActor using withCheckedContinuation.
        // The callback fires on a private SFSpeech background queue but continuation.resume
        // is thread-safe regardless of which thread calls it.
        return await withCheckedContinuation { continuation in
            var didResume = false

            // Safety timeout: prevents a hung continuation if the recognizer goes silent
            // (neither result nor error). Allow up to 5 minutes for long recordings.
            let timeoutWork = DispatchWorkItem {
                if !didResume {
                    didResume = true
                    print("[SingCoach] Transcription: 5-minute timeout reached, aborting")
                    continuation.resume(returning: .failure(TranscriptionError.timeout))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeoutWork)

            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    if !didResume {
                        didResume = true
                        timeoutWork.cancel()
                        let transcript = result.bestTranscription.formattedString
                        print("[SingCoach] Transcription done: \(transcript.split(separator: " ").count) words")
                        continuation.resume(returning: .success(transcript))
                    }
                }
                if let error {
                    if !didResume {
                        didResume = true
                        timeoutWork.cancel()
                        print("[SingCoach] Transcription failed: \(error)")
                        continuation.resume(returning: .failure(error))
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
