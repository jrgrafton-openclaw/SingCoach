import MusicKit
import SwiftUI

// MusicKitService.swift
// Build 1 (com.jrgrafton.singcoach): Full MusicKit restored.
// MusicKit capability is enabled on the App ID in Developer Portal.
// Note: Song type is fully qualified as MusicKit.Song to avoid clash with SwiftData Song model.

@MainActor
final class MusicKitService: ObservableObject {
    static let shared = MusicKitService()

    @Published var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @Published var isPlaying: Bool = false
    @Published var currentTrackID: String? = nil
    @Published var playbackTime: TimeInterval = 0
    @Published var trackDuration: TimeInterval = 0

    private var stateObservationTask: Task<Void, Never>? = nil

    private init() {
        startObservingPlaybackState()
    }

    private func startObservingPlaybackState() {
        stateObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                let player = ApplicationMusicPlayer.shared
                let playing = player.state.playbackStatus == .playing
                let time = player.playbackTime
                // Duration comes from the current queue entry's song
                let duration: TimeInterval
                if case .song(let s) = player.queue.currentEntry?.item {
                    duration = s.duration ?? 0
                } else {
                    duration = 0
                }
                await MainActor.run {
                    self?.isPlaying = playing
                    self?.playbackTime = time
                    self?.trackDuration = duration
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func requestAuthorization() async {
        authorizationStatus = await MusicAuthorization.request()
    }

    func searchSongs(query: String) async throws -> [MusicKit.Song] {
        guard authorizationStatus == .authorized else {
            throw MusicKitError.notAuthorized
        }
        var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Song.self])
        request.limit = 25
        let response = try await request.response()
        print("[MusicKit] Search '\(query)': \(response.songs.count) results")
        return Array(response.songs)
    }

    /// Play the given song. If it's already the current track and is paused, resumes it.
    func play(song: MusicKit.Song) async throws {
        guard authorizationStatus == .authorized else { return }
        let player = ApplicationMusicPlayer.shared
        // If same track is already queued, just resume
        if currentTrackID == song.id.rawValue && player.state.playbackStatus == .paused {
            try await player.play()
            return
        }
        let entry = ApplicationMusicPlayer.Queue.Entry(song)
        player.queue = ApplicationMusicPlayer.Queue([entry])
        try await player.play()
        currentTrackID = song.id.rawValue
    }

    func pause() {
        ApplicationMusicPlayer.shared.pause()
    }

    func togglePlayback(song: MusicKit.Song) async throws {
        if isPlaying && currentTrackID == song.id.rawValue {
            pause()
        } else {
            try await play(song: song)
        }
    }

    var currentPlaybackTime: TimeInterval {
        ApplicationMusicPlayer.shared.playbackTime
    }

    func seek(to time: TimeInterval) {
        ApplicationMusicPlayer.shared.playbackTime = max(0, time)
    }

    func skipBackward(seconds: TimeInterval = 15) {
        seek(to: currentPlaybackTime - seconds)
    }

    func skipForward(seconds: TimeInterval = 15) {
        seek(to: currentPlaybackTime + seconds)
    }

    // MARK: - Static scoring helpers

    static func karaokeScore(
        candidateTitle: String,
        candidateArtist: String,
        originalTitle: String,
        originalArtist: String
    ) -> Double {
        let karaokeKeywords = ["karaoke", "instrumental", "backing track", "minus one", "no vocals", "in the style of"]
        let titleLower = candidateTitle.lowercased()
        let artistLower = candidateArtist.lowercased()
        let hasKaraokeKeyword = karaokeKeywords.contains { titleLower.contains($0) || artistLower.contains($0) }
        var cleanTitle = titleLower
        for kw in karaokeKeywords { cleanTitle = cleanTitle.replacingOccurrences(of: kw, with: "") }
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleSimilarity = stringSimilarity(cleanTitle, originalTitle.lowercased())
        let artistSimilarity = stringSimilarity(artistLower, originalArtist.lowercased()) * 0.3
        let keywordBonus = hasKaraokeKeyword ? 0.4 : 0.0
        return keywordBonus + (titleSimilarity * 0.45) + (artistSimilarity * 0.15)
    }

    static func stringSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        let aWords = Set(a.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        let bWords = Set(b.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        guard !aWords.isEmpty || !bWords.isEmpty else { return 0.0 }
        let intersection = aWords.intersection(bWords).count
        let union = aWords.union(bWords).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}

enum MusicKitError: LocalizedError {
    case notAuthorized
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Please allow Apple Music access in Settings"
        }
    }
}
