import Foundation

// MARK: - Apple Music REST API Models

struct AppleMusicSearchResponse: Codable {
    let results: AppleMusicSearchResults
}

struct AppleMusicSearchResults: Codable {
    let songs: AppleMusicCollection<AppleMusicSong>?
}

struct AppleMusicCollection<T: Codable>: Codable {
    let data: [T]
}

struct AppleMusicSong: Codable, Identifiable {
    let id: String
    let attributes: AppleMusicSongAttributes
}

struct AppleMusicSongAttributes: Codable {
    let name: String
    let artistName: String
    let albumName: String?
    let durationInMillis: Int?
    let artwork: AppleMusicArtwork?
    let url: String?
}

struct AppleMusicArtwork: Codable {
    let url: String // template URL: replace {w} and {h} with pixel dimensions
    let width: Int?
    let height: Int?

    func imageURL(size: Int = 300) -> URL? {
        URL(string: url
            .replacingOccurrences(of: "{w}", with: "\(size)")
            .replacingOccurrences(of: "{h}", with: "\(size)"))
    }
}

// MARK: - Apple Music Service

/// Searches the Apple Music catalog using the REST API.
/// No MusicKit entitlement required — uses a pre-generated developer token (JWT).
/// Used for background artwork/metadata fetching when MusicKit is not authorized.
@MainActor
final class AppleMusicService: ObservableObject {

    static let shared = AppleMusicService()

    // Pre-generated developer token (valid 180 days from 2026-02-20 build)
    // Generated from: team=B5X96QDRF4, keyID=7UKLD4C2CC, .p8 key via ES256 JWT
    static let developerToken = "eyJhbGciOiJFUzI1NiIsImtpZCI6IjdVS0xENEMyQ0MiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJCNVg5NlFEUkY0IiwiaWF0IjoxNzcxNTcxNjQ3LCJleHAiOjE3ODcxMjM2NDd9.GMJfaE3MXZb2nv3IAAHaMFSo3yYzb0LOm9mye3SdwwdGwQy175cNXJHUz7pulpG9TZchEgwndzySNyxCfynYwQ"

    private init() {}

    /// Search the Apple Music catalog for songs matching the query.
    func searchSongs(query: String) async throws -> [AppleMusicSong] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.music.apple.com/v1/catalog/us/search?term=\(encoded)&types=songs&limit=25") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(Self.developerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[AppleMusicService] HTTP \(httpResponse.statusCode): \(body)")
            throw AppleMusicError.httpError(httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: data)
        let songs = decoded.results.songs?.data ?? []
        print("[AppleMusicService] search '\(query)': \(songs.count) results")
        return songs
    }

    /// Find the best-matching song for a title + artist pair.
    func findBestMatch(songTitle: String, artist: String) async throws -> AppleMusicSong? {
        let query = "\(songTitle) \(artist)"
        let results = try await searchSongs(query: query)
        guard !results.isEmpty else { return nil }

        var bestMatch: AppleMusicSong? = nil
        var bestScore: Double = 0

        for candidate in results {
            let candidateKey = "\(candidate.attributes.name.lowercased()) \(candidate.attributes.artistName.lowercased())"
            let targetKey = "\(songTitle.lowercased()) \(artist.lowercased())"
            let score = stringSimilarity(candidateKey, targetKey)
            if score > bestScore {
                bestScore = score
                bestMatch = candidate
            }
        }

        print("[AppleMusicService] Best match for '\(songTitle)': score=\(String(format: "%.2f", bestScore))")
        return bestScore >= 0.4 ? bestMatch : nil
    }

    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        let aWords = Set(a.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        let bWords = Set(b.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        guard !aWords.isEmpty || !bWords.isEmpty else { return 0.0 }
        let intersection = aWords.intersection(bWords).count
        let union = aWords.union(bWords).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    enum AppleMusicError: LocalizedError {
        case httpError(Int)
        var errorDescription: String? {
            switch self {
            case .httpError(let code):
                return "Apple Music API error (HTTP \(code)). Check developer token."
            }
        }
    }
}
