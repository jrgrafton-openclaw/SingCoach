import Foundation
import SwiftData
import Combine

@MainActor
final class SongsViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [LRCLibSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var showAddSheet = false

    private let lrcLib = LRCLibService.shared

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        errorMessage = nil

        do {
            searchResults = try await lrcLib.search(query: query)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("[SingCoach] LRCLib search error: \(error)")
        }
        isSearching = false
    }

    func addSong(from result: LRCLibSearchResult, modelContext: ModelContext) async {
        print("[SingCoach] Adding song: \(result.trackName) by \(result.artistName)")

        // Use the search result's lyrics directly — the search endpoint returns better-formatted
        // lyrics (with proper paragraph breaks) than the /api/get endpoint. Only fall back to
        // getLyrics() if the search result had no lyrics at all.
        var lyricsResult = result
        if result.syncedLyrics == nil && result.plainLyrics == nil {
            // Try by exact LRCLIB id first (guaranteed to get the same record)
            if let byId = try? await lrcLib.getLyricsById(result.id) {
                lyricsResult = byId
            }
        }

        // Parse lyrics — prefer plain lyrics for paragraph structure when synced lacks markers
        var lines: [LyricsLine] = []
        var hasSynced = false

        if let synced = lyricsResult.syncedLyrics, !synced.isEmpty {
            let syncedLines = lrcLib.parseLRCLyrics(synced)
            hasSynced = syncedLines.contains { $0.timestampSeconds != nil }

            // If the plain lyrics have richer paragraph structure (more blank-line separators),
            // use plain lyrics structure but only for section markers — not for display.
            // Actually: just use the plain lyrics paragraph markers to annotate synced lines.
            if let plain = lyricsResult.plainLyrics, !plain.isEmpty {
                lines = lrcLib.parseSyncedWithPlainStructure(synced: synced, plain: plain)
            } else {
                lines = syncedLines
            }
        } else if let plain = lyricsResult.plainLyrics, !plain.isEmpty {
            lines = lrcLib.parsePlainLyrics(plain)
        }

        let song = Song(
            title: result.trackName,
            artist: result.artistName,
            lyricsLines: lines,
            karaokeSearchStatus: "idle"
        )

        modelContext.insert(song)
        do {
            try modelContext.save()
            print("[SingCoach] Song saved: \(song.title)")
        } catch {
            print("[SingCoach] Failed to save song: \(error)")
        }

        AnalyticsService.shared.songAdded(source: "lrclib", hasSyncedLyrics: hasSynced)

        // Dismiss the sheet NOW — song is already saved and will appear in the list
        showAddSheet = false

        // Fetch artwork via MusicKit (authorized) in background
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await autoFetchArtworkViaMusicKit(for: song, modelContext: modelContext)
        }
    }

    func addManualSong(title: String, artist: String, modelContext: ModelContext) {
        let song = Song(title: title, artist: artist, karaokeSearchStatus: "idle")
        modelContext.insert(song)
        try? modelContext.save()
        AnalyticsService.shared.songAdded(source: "manual", hasSyncedLyrics: false)
        showAddSheet = false
        print("[SingCoach] Manual song added: \(title)")

        // Fetch artwork via MusicKit
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await autoFetchArtworkViaMusicKit(for: song, modelContext: modelContext)
        }
    }

    /// Fetch artwork via MusicKit (requires user authorization, which the app requests on launch).
    /// Falls back gracefully if MusicKit is not authorized.
    private func autoFetchArtworkViaMusicKit(for song: Song, modelContext: ModelContext) async {
        let musicKit = MusicKitService.shared
        guard musicKit.authorizationStatus == .authorized else {
            print("[SingCoach] MusicKit not authorized — skipping artwork fetch for \(song.title)")
            return
        }
        do {
            let results = try await musicKit.searchSongs(query: "\(song.title) \(song.artist)")
            guard let best = results.first else { return }
            if let artURL = best.artwork?.url(width: 300, height: 300)?.absoluteString {
                song.artworkURL = artURL
                song.appleMusicID = best.id.rawValue
                try? modelContext.save()
                print("[SingCoach] Artwork set via MusicKit for \(song.title)")
            }
        } catch {
            print("[SingCoach] MusicKit artwork fetch error for \(song.title): \(error)")
        }
    }
}
