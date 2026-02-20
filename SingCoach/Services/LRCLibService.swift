import Foundation

struct LRCLibSearchResult: Codable, Identifiable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?

    enum CodingKeys: String, CodingKey {
        case id
        case trackName
        case artistName
        case albumName
        case duration
        case syncedLyrics
        case plainLyrics
    }
}

@MainActor
final class LRCLibService {
    static let shared = LRCLibService()
    private let baseURL = "https://lrclib.net/api"

    private init() {}

    func search(query: String) async throws -> [LRCLibSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search?q=\(encoded)") else {
            throw URLError(.badURL)
        }

        print("[SingCoach] LRCLib search: \(query)")
        let (data, _) = try await URLSession.shared.data(from: url)
        let results = try JSONDecoder().decode([LRCLibSearchResult].self, from: data)
        print("[SingCoach] LRCLib found \(results.count) results")
        return results
    }

    func getLyrics(artistName: String, trackName: String) async throws -> LRCLibSearchResult? {
        guard let encodedArtist = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTrack = trackName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/get?artist_name=\(encodedArtist)&track_name=\(encodedTrack)") else {
            throw URLError(.badURL)
        }

        print("[SingCoach] LRCLib get lyrics: \(artistName) - \(trackName)")
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            print("[SingCoach] LRCLib 404 - no lyrics found")
            return nil
        }
        return try JSONDecoder().decode(LRCLibSearchResult.self, from: data)
    }

    // Parse LRC format timestamps: [mm:ss.xx] or [mm:ss.xxx]
    func parseLRCLyrics(_ lrc: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        var index = 0

        for rawLine in lrc.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Parse timestamp [mm:ss.xx]
            if let timestampRange = line.range(of: #"^\[(\d{2}):(\d{2}\.\d+)\](.*)$"#, options: .regularExpression) {
                let _ = timestampRange
                let pattern = #"^\[(\d{2}):(\d{2}\.\d+)\](.*)$"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let minutesRange = Range(match.range(at: 1), in: line)!
                    let secondsRange = Range(match.range(at: 2), in: line)!
                    let textRange = Range(match.range(at: 3), in: line)!

                    let minutes = Double(line[minutesRange]) ?? 0
                    let seconds = Double(line[secondsRange]) ?? 0
                    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)

                    if !text.isEmpty {
                        let timestamp = minutes * 60 + seconds
                        lines.append(LyricsLine(index: index, text: text, timestampSeconds: timestamp))
                        index += 1
                    }
                }
            } else if !line.hasPrefix("[") {
                // Plain text line
                lines.append(LyricsLine(index: index, text: line))
                index += 1
            }
        }

        return lines
    }

    func parsePlainLyrics(_ plain: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        var index = 0
        for line in plain.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(LyricsLine(index: index, text: trimmed))
                index += 1
            }
        }
        return lines
    }
}
