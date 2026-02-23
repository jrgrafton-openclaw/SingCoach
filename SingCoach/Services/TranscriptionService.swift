import Foundation
import Speech
import AVFoundation
import Combine

protocol TranscriptionProtocol: AnyObject {
    func transcribe(audioFileURL: URL) async -> Result<String, Error>
}

@MainActor
final class TranscriptionService: ObservableObject, TranscriptionProtocol {
    @Published var isTranscribing = false
    /// Progress string shown in UI during chunked transcription, e.g. "Chunk 3 / 24"
    /// Empty string when not chunking (short audio or idle).
    @Published var chunkProgress: String = ""

    // Apple documents a hard 1-minute limit per SFSpeechRecognitionRequest.
    // We use 55s chunks to stay safely under it.
    private static let chunkDuration: Double = 55.0

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

    // MARK: - Public entry point

    func transcribe(audioFileURL: URL) async -> Result<String, Error> {
        guard let recognizer, recognizer.isAvailable else {
            print("[SingCoach] SFSpeechRecognizer not available")
            return .failure(TranscriptionError.recognizerUnavailable)
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            print("[SingCoach] Transcription: audio file missing at \(audioFileURL.path)")
            return .failure(TranscriptionError.audioFileMissing)
        }

        isTranscribing = true
        defer { isTranscribing = false }

        // Determine duration — if short enough, use the simpler URL-based path.
        let asset = AVURLAsset(url: audioFileURL)
        let durationSeconds: Double
        do {
            let cmDuration = try await asset.load(.duration)
            durationSeconds = cmDuration.seconds
        } catch {
            // Fall back to URL-based approach if we can't read duration
            print("[SingCoach] Transcription: could not read duration, using URL-based fallback: \(error)")
            return await transcribeURL(audioFileURL: audioFileURL, recognizer: recognizer)
        }

        print("[SingCoach] Transcription started: \(audioFileURL.lastPathComponent) (\(String(format: "%.0f", durationSeconds))s)")

        if durationSeconds <= Self.chunkDuration {
            return await transcribeURL(audioFileURL: audioFileURL, recognizer: recognizer)
        } else {
            let chunkCount = Int(ceil(durationSeconds / Self.chunkDuration))
            print("[SingCoach] Transcription: long audio — splitting into \(chunkCount) × \(Int(Self.chunkDuration))s chunks")
            return await transcribeChunked(audioFileURL: audioFileURL, recognizer: recognizer, totalDuration: durationSeconds)
        }
    }

    // MARK: - URL-based transcription (≤ 55s audio)
    //
    // All recognition state is accessed on DispatchQueue.main (the @MainActor executor),
    // serialising reads/writes to didResume and bestTranscript without any explicit lock.
    // This eliminates the Swift 6 data race that previously caused a double-resume crash:
    //   - recognition callback (SFSpeech background queue) → dispatched to main
    //   - timeout DispatchWorkItem (global queue) → dispatched to main
    // Both arrive on main serially, so there is no TOCTOU race on didResume.

    private func transcribeURL(audioFileURL: URL, recognizer: SFSpeechRecognizer) async -> Result<String, Error> {
        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        // Lesson 27: do NOT set requiresOnDeviceRecognition = true (hard ~60s cap)

        return await withCheckedContinuation { continuation in
            var didResume = false
            var bestTranscript = ""

            let timeoutWork = DispatchWorkItem {
                DispatchQueue.main.async {
                    guard !didResume else { return }
                    didResume = true
                    if !bestTranscript.isEmpty {
                        print("[SingCoach] Transcription (URL): timeout — returning partial (\(bestTranscript.split(separator: " ").count) words)")
                        continuation.resume(returning: .success(bestTranscript))
                    } else {
                        continuation.resume(returning: .failure(TranscriptionError.timeout))
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeoutWork)

            recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    if let result {
                        bestTranscript = result.bestTranscription.formattedString
                        if result.isFinal {
                            guard !didResume else { return }
                            didResume = true
                            timeoutWork.cancel()
                            print("[SingCoach] Transcription (URL) done: \(bestTranscript.split(separator: " ").count) words")
                            continuation.resume(returning: .success(bestTranscript))
                        }
                    }
                    if let error {
                        guard !didResume else { return }
                        didResume = true
                        timeoutWork.cancel()
                        if !bestTranscript.isEmpty {
                            print("[SingCoach] Transcription (URL): error after partial — using partial. Error: \(error)")
                            continuation.resume(returning: .success(bestTranscript))
                        } else {
                            print("[SingCoach] Transcription (URL) failed: \(error)")
                            continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chunked transcription (> 55s audio)
    //
    // Reads PCM frames from the audio file in ~55s slices, sends each slice as a
    // SFSpeechAudioBufferRecognitionRequest, and concatenates all results.
    // This is the standard community approach for bypassing Apple's 1-min per-request cap.

    private func transcribeChunked(audioFileURL: URL, recognizer: SFSpeechRecognizer, totalDuration: Double) async -> Result<String, Error> {
        guard let audioFile = try? AVAudioFile(forReading: audioFileURL) else {
            return .failure(TranscriptionError.audioFileMissing)
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let framesPerChunk = AVAudioFrameCount(Self.chunkDuration * sampleRate)
        let totalFrames = audioFile.length
        let totalChunks = Int(ceil(Double(totalFrames) / Double(framesPerChunk)))

        var parts: [String] = []
        var chunkIndex = 0
        var startFrame: AVAudioFramePosition = 0

        while startFrame < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - startFrame)
            let framesToRead = min(framesPerChunk, remaining)
            chunkIndex += 1

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                print("[SingCoach] Transcription chunk \(chunkIndex)/\(totalChunks): could not allocate buffer, skipping")
                startFrame += AVAudioFramePosition(framesToRead)
                continue
            }

            audioFile.framePosition = startFrame
            do {
                try audioFile.read(into: buffer, frameCount: framesToRead)
            } catch {
                print("[SingCoach] Transcription chunk \(chunkIndex)/\(totalChunks): read error: \(error), skipping")
                startFrame += AVAudioFramePosition(framesToRead)
                continue
            }

            let chunkStart = String(format: "%.0f", Double(startFrame) / sampleRate)
            chunkProgress = "Chunk \(chunkIndex) / \(totalChunks)"
            print("[SingCoach] Transcription chunk \(chunkIndex)/\(totalChunks): recognizing (\(chunkStart)s…)")

            let chunkResult = await transcribeBuffer(buffer: buffer, recognizer: recognizer, chunkLabel: "\(chunkIndex)/\(totalChunks)")
            switch chunkResult {
            case .success(let text):
                if !text.isEmpty {
                    parts.append(text)
                }
            case .failure(let error):
                // A single chunk failure is not fatal — log and continue
                print("[SingCoach] Transcription chunk \(chunkIndex)/\(totalChunks): failed (\(error)), continuing")
            }

            startFrame += AVAudioFramePosition(framesToRead)

            // Brief inter-chunk pause — gives the ASC network endpoint time to settle
            // and avoids hitting rate limits on back-to-back requests.
            if startFrame < totalFrames {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }

        chunkProgress = ""
        let fullTranscript = parts.joined(separator: " ")
        if fullTranscript.isEmpty {
            print("[SingCoach] Transcription (chunked): all chunks failed — no transcript")
            return .failure(TranscriptionError.timeout)
        }

        print("[SingCoach] Transcription (chunked) done: \(parts.count)/\(totalChunks) chunks, \(fullTranscript.split(separator: " ").count) total words")
        return .success(fullTranscript)
    }

    // MARK: - Single buffer transcription (one chunk)

    private func transcribeBuffer(buffer: AVAudioPCMBuffer, recognizer: SFSpeechRecognizer, chunkLabel: String) async -> Result<String, Error> {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        // Append the entire chunk buffer then signal end-of-audio
        // Note: appendAudioPCMBuffer was renamed to append(_:) in Swift 3
        request.append(buffer)
        request.endAudio()

        return await withCheckedContinuation { continuation in
            var didResume = false
            var bestTranscript = ""

            // Per-chunk timeout: 90s gives plenty of headroom for a 55s audio chunk
            let timeoutWork = DispatchWorkItem {
                DispatchQueue.main.async {
                    guard !didResume else { return }
                    didResume = true
                    if !bestTranscript.isEmpty {
                        print("[SingCoach] Chunk \(chunkLabel): timeout — using partial (\(bestTranscript.split(separator: " ").count) words)")
                        continuation.resume(returning: .success(bestTranscript))
                    } else {
                        print("[SingCoach] Chunk \(chunkLabel): timeout with no partial")
                        continuation.resume(returning: .failure(TranscriptionError.timeout))
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeoutWork)

            recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    if let result {
                        bestTranscript = result.bestTranscription.formattedString
                        if result.isFinal {
                            guard !didResume else { return }
                            didResume = true
                            timeoutWork.cancel()
                            print("[SingCoach] Chunk \(chunkLabel): done (\(bestTranscript.split(separator: " ").count) words)")
                            continuation.resume(returning: .success(bestTranscript))
                        }
                    }
                    if let error {
                        guard !didResume else { return }
                        didResume = true
                        timeoutWork.cancel()
                        if !bestTranscript.isEmpty {
                            print("[SingCoach] Chunk \(chunkLabel): error after partial — using partial. Error: \(error)")
                            continuation.resume(returning: .success(bestTranscript))
                        } else {
                            print("[SingCoach] Chunk \(chunkLabel): failed with no partial: \(error)")
                            continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Errors

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
