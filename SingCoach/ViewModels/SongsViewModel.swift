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

        // Fetch full lyrics if we don't have them
        var lyricsResult = result
        if result.syncedLyrics == nil && result.plainLyrics == nil {
            lyricsResult = (try? await lrcLib.getLyrics(
                artistName: result.artistName,
                trackName: result.trackName
            )) ?? result
        }

        // Parse lyrics
        var lines: [LyricsLine] = []
        var hasSynced = false
        if let synced = lyricsResult.syncedLyrics, !synced.isEmpty {
            lines = lrcLib.parseLRCLyrics(synced)
            hasSynced = lines.contains { $0.timestampSeconds != nil }
        } else if let plain = lyricsResult.plainLyrics, !plain.isEmpty {
            lines = lrcLib.parsePlainLyrics(plain)
        }

        let song = Song(
            title: result.trackName,
            artist: result.artistName,
            lyricsLines: lines
        )

        modelContext.insert(song)
        do {
            try modelContext.save()
            print("[SingCoach] Song saved: \(song.title)")
        } catch {
            print("[SingCoach] Failed to save song: \(error)")
        }

        AnalyticsService.shared.songAdded(source: "lrclib", hasSyncedLyrics: hasSynced)
        showAddSheet = false
    }

    func addManualSong(title: String, artist: String, modelContext: ModelContext) {
        let song = Song(title: title, artist: artist)
        modelContext.insert(song)
        try? modelContext.save()
        AnalyticsService.shared.songAdded(source: "manual", hasSyncedLyrics: false)
        showAddSheet = false
        print("[SingCoach] Manual song added: \(title)")
    }
}
