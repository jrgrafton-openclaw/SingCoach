import Foundation
import AVFoundation
import Combine

@MainActor
protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var playbackRate: Float { get set }
    var onTrackFinished: (() -> Void)? { get set }
    func load(url: URL) throws
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
}

enum AudioPlaybackError: LocalizedError {
    case fileNotFound
    var errorDescription: String? { "Audio file not found." }
}

@MainActor
final class AudioPlaybackService: NSObject, ObservableObject, AudioPlayerProtocol {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var loadError: String? = nil
    var playbackRate: Float = 1.0 {
        didSet { audioPlayer?.rate = playbackRate }
    }
    var onTrackFinished: (() -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) throws {
        // Bug 8 fix: verify file exists before attempting load
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = "Audio file not found."
            throw AudioPlaybackError.fileNotFound
        }
        loadError = nil
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        audioPlayer?.enableRate = true
        audioPlayer?.rate = playbackRate
        duration = audioPlayer?.duration ?? 0
        currentTime = 0
        print("[SingCoach] AudioPlayer loaded: \(url.lastPathComponent), duration=\(duration)s")
    }

    func play() {
        // Bug 8 fix: guard against nil player (silent load failure)
        guard let audioPlayer else {
            print("[SingCoach] AudioPlayer: play() called but player is nil")
            return
        }
        audioPlayer.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        timer?.invalidate()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.audioPlayer?.currentTime ?? 0
            }
        }
    }
}

extension AudioPlaybackService: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        timer?.invalidate()
        onTrackFinished?()
        print("[SingCoach] AudioPlayer finished playing")
    }
}
