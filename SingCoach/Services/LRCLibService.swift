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

    /// Fetch a specific LRCLIB record by its integer ID.
    /// This guarantees we get the exact same record that came back from search,
    /// which has better paragraph structure than the /api/get name-lookup endpoint.
    func getLyricsById(_ id: Int) async throws -> LRCLibSearchResult? {
        guard let url = URL(string: "\(baseURL)/get/\(id)") else { throw URLError(.badURL) }
        print("[SingCoach] LRCLib get by id: \(id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        return try JSONDecoder().decode(LRCLibSearchResult.self, from: data)
    }

    /// Parse synced LRC lyrics but use the plain lyrics' blank-line structure to inject
    /// paragraph break markers (section == "¶") at the right places.
    ///
    /// Strategy: build a normalized index of plain-lyrics paragraph starts, then match
    /// each synced line to its plain counterpart and inherit the paragraph marker.
    func parseSyncedWithPlainStructure(synced: String, plain: String) -> [LyricsLine] {
        // Parse both independently
        let syncedLines = parseLRCLyrics(synced)
        let plainLines = parsePlainLyrics(plain)

        // Build a set of line indices in plainLines that have a paragraph break
        let plainBreakTexts: Set<String> = Set(
            plainLines.filter { $0.section == "¶" }.map { normalizeText($0.text) }
        )

        // Apply those breaks to synced lines by text match
        var result: [LyricsLine] = []
        var usedBreaks = Set<String>()

        for (i, line) in syncedLines.enumerated() {
            let norm = normalizeText(line.text)
            if plainBreakTexts.contains(norm) && !usedBreaks.contains(norm) && i > 0 {
                // First synced line that matches a plain break text → inject break marker
                usedBreaks.insert(norm)
                let marked = LyricsLine(
                    index: line.index,
                    text: line.text,
                    timestampSeconds: line.timestampSeconds,
                    section: "¶"
                )
                result.append(marked)
            } else {
                result.append(line)
            }
        }
        return result
    }

    private func normalizeText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .trimmingCharacters(in: .whitespaces)
    }

    // Parse LRC format timestamps: [mm:ss.xx] or [mm:ss.xxx]
    func parseLRCLyrics(_ lrc: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        var index = 0
        var pendingNewParagraph = false

        for rawLine in lrc.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Blank line = paragraph break marker
            if line.isEmpty {
                pendingNewParagraph = true
                continue
            }

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
                        // Use "¶" sentinel to mark unnamed paragraph breaks
                        let section: String? = (pendingNewParagraph && index > 0) ? "¶" : nil
                        lines.append(LyricsLine(index: index, text: text, timestampSeconds: timestamp, section: section))
                        index += 1
                        pendingNewParagraph = false
                    } else {
                        // Empty-text timestamp line also counts as a paragraph break
                        pendingNewParagraph = true
                    }
                }
            } else if !line.hasPrefix("[") {
                // Plain text line (no timestamp)
                let section: String? = (pendingNewParagraph && index > 0) ? "¶" : nil
                lines.append(LyricsLine(index: index, text: line, section: section))
                index += 1
                pendingNewParagraph = false
            }
            // Metadata lines like [ti:], [ar:] etc. — skip and treat as separators
            else {
                pendingNewParagraph = true
            }
        }

        return lines
    }

    func parsePlainLyrics(_ plain: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        var index = 0
        var pendingNewParagraph = false
        for line in plain.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                pendingNewParagraph = true
                continue
            }
            let section: String? = (pendingNewParagraph && index > 0) ? "¶" : nil
            lines.append(LyricsLine(index: index, text: trimmed, section: section))
            index += 1
            pendingNewParagraph = false
        }
        return lines
    }
}
