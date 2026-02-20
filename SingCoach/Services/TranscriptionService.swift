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

        isTranscribing = true
        defer { isTranscribing = false }

        print("[SingCoach] Transcription started: \(audioFileURL.lastPathComponent)")

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        do {
            let transcript = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result, result.isFinal {
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
            print("[SingCoach] Transcription done: \(transcript.split(separator: " ").count) words")
            return .success(transcript)
        } catch {
            print("[SingCoach] Transcription failed: \(error)")
            return .failure(error)
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available on this device."
        case .permissionDenied:
            return "Speech recognition permission was denied."
        }
    }
}
