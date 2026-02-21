import XCTest
@testable import SingCoach

// Tests for smart paragraph break detection in LyricsView.paragraphBreakIndices
// Uses the actual "Losing My Religion" LRC data embedded inline to avoid network calls.
// Expected paragraph breaks verified manually against the reference formatting.

@MainActor
final class LyricsParagraphDetectionTests: XCTestCase {

    // Minimal LyricsLine stand-in for testing purposes
    // We build real LyricsLine objects via LRCLibService and pass them into a
    // helper that mirrors the LyricsView.paragraphBreakIndices logic.

    /// Mirror of LyricsView.paragraphBreakIndices — extracted for unit testing.
    func computeBreaks(from lines: [LyricsLine]) -> Set<Int> {
        guard lines.count > 1 else { return [] }

        let hasAnySection = lines.contains { $0.section != nil }
        if hasAnySection {
            var result = Set<Int>()
            for (i, line) in lines.enumerated() where i > 0 && line.section != nil {
                result.insert(i)
            }
            return result
        }

        var rawBreaks = Set<Int>()

        // Repeated block detection
        let BLOCK = 3
        if lines.count >= BLOCK {
            var firstSeen: [String: Int] = [:]
            var blockStarts = Set<Int>()

            for i in 0...(lines.count - BLOCK) {
                let fp = (0..<BLOCK).map { j in
                    lines[i + j].text.lowercased()
                        .components(separatedBy: .alphanumerics.inverted)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }.joined(separator: "|")

                if let prev = firstSeen[fp] {
                    if i >= prev + BLOCK {
                        blockStarts.insert(prev)
                        blockStarts.insert(i)
                    }
                } else {
                    firstSeen[fp] = i
                }
            }

            for pos in blockStarts where pos > 0 {
                rawBreaks.insert(pos)
            }
        }

        // Timestamp gap fallback
        let hasSynced = lines.contains { $0.timestampSeconds != nil }
        if hasSynced {
            let timestamps = lines.compactMap { $0.timestampSeconds }
            if timestamps.count > 2 {
                let gaps = zip(timestamps, timestamps.dropFirst()).map { $1 - $0 }
                let sorted = gaps.sorted()
                let median = sorted[sorted.count / 2]
                let threshold = max(6.0, median * 1.8)
                for i in 1..<lines.count {
                    guard let t1 = lines[i - 1].timestampSeconds,
                          let t2 = lines[i].timestampSeconds else { continue }
                    if t2 - t1 >= threshold {
                        rawBreaks.insert(i)
                    }
                }
            }
        }

        // Collapse consecutive breaks
        let sorted = rawBreaks.sorted()
        var result = Set<Int>()
        var prev = -99
        for b in sorted {
            if b - prev > 1 { result.insert(b) }
            prev = b
        }
        return result
    }

    // MARK: - Losing My Religion test

    func testLosingMyReligionParagraphBreaks() {
        // Embedded LRC data for "Losing My Religion" by R.E.M. (from LRCLIB)
        // This is the real production data the app uses.
        let lrc = """
[00:14.53] Oh, life, it's bigger
[00:20.67] It's bigger than you
[00:22.80] And you are not me
[00:25.93] The lengths that I will go to
[00:29.94] The distance in your eyes
[00:35.90] Oh, no, I've said too much
[00:42.31] I set it up
[00:45.80] That's me in the corner
[00:49.85] That's me in the spotlight
[00:52.92] Losing my religion
[00:56.90] Trying to keep up with you
[01:01.51] And I don't know if I can do it
[01:06.29] Oh, no, I've said too much
[01:11.68] I haven't said enough
[01:15.85] I thought that I heard you laughing
[01:19.54] I thought that I heard you sing
[01:24.59] I think I thought I saw you try
[01:32.39] Every whisper
[01:34.84] Of every waking hour
[01:38.01] I'm choosing my confessions
[01:42.91] Trying to keep an eye on you
[01:47.46] Like a hurt, lost and blinded fool, fool
[01:52.66] Oh, no, I've said too much
[01:58.67] I set it up
[02:02.59] Consider this
[02:05.39] Consider this, the hint of the century
[02:10.30] Consider this, the slip
[02:15.00] That brought me to my knees, failed
[02:19.14] What if all these fantasies come
[02:23.03] Flailing around
[02:25.66] Now I've said too much
[02:32.32] I thought that I heard you laughing
[02:35.65] I thought that I heard you sing
[02:41.33] I think I thought I saw you try
[02:57.11] But that was just a dream
[03:00.73] That was just a dream
[03:03.70] That's me in the corner
[03:06.98] That's me in the spotlight
[03:10.49] Losing my religion
[03:14.77] Trying to keep up with you
[03:18.88] And I don't know if I can do it
[03:24.43] Oh, no, I've said too much
[03:29.46] I haven't said enough
[03:33.60] I thought that I heard you laughing
[03:37.59] I thought that I heard you sing
[03:42.61] I think I thought I saw you try
[03:50.42] But that was just a dream
[03:54.19] Try, cry, why try?
[03:58.57] That was just a dream
[04:01.29] Just a dream
[04:03.32] Just a dream, dream
"""
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics(lrc)

        XCTAssertEqual(lines.count, 51, "Should parse 51 lyric lines")

        let breaks = computeBreaks(from: lines)

        // Verified expected breaks matching reference formatting:
        // [7]  "That's me in the corner"  — chorus starts here (repeated block)
        // [17] "Every whisper"            — gap break (7.8s) + new section
        // [31] "I thought that I heard…"  — repeated bridge block
        // [34] "But that was just a dream"— large gap (15.8s)
        // [36] "That's me in the corner"  — chorus repeat
        // [46] "But that was just a dream"— outro / repeated block
        let expected: Set<Int> = [7, 17, 31, 34, 36, 46]

        // All expected breaks must be present
        for b in expected {
            XCTAssertTrue(breaks.contains(b), "Expected paragraph break at index \(b) ('\(lines[b].text)')")
        }

        // No break at index 0 (first line is never a break)
        XCTAssertFalse(breaks.contains(0), "First line should never be a paragraph break")

        // No spurious breaks inside the verse (lines 1–6 should all be in the same paragraph)
        for i in 1...6 {
            XCTAssertFalse(breaks.contains(i), "Line \(i) should NOT be a paragraph break (same verse as line 0)")
        }
    }

    // MARK: - Repeated block baseline

    func testRepeatedChorusDetected() {
        // Simple case: 4 lines + 3-line chorus + bridge + same 3-line chorus again
        let chorus = ["That's me in the corner", "That's me in the spotlight", "Losing my religion"]
        let allLines = [
            "Oh life", "It's bigger", "And you are not me", "The lengths"
        ] + chorus + [
            "Every whisper", "Of every waking hour"
        ] + chorus  // repeated

        let lines = allLines.enumerated().map { (i, text) in
            LyricsLine(index: i, text: text, timestampSeconds: Double(i) * 4.0)
        }

        let breaks = computeBreaks(from: lines)

        // Lines: [0-3] verse, [4-6] chorus, [7-8] bridge, [9-11] chorus repeat
        // Repeated-block detection marks [4] (first chorus) and [9] (second chorus).
        // [7] (bridge) has unique text and equal timestamp spacing — no break expected from this algorithm alone.
        XCTAssertTrue(breaks.contains(4), "First chorus occurrence should be a paragraph break")
        XCTAssertTrue(breaks.contains(9), "Repeated chorus should be a paragraph break")
        // The verse itself should not be split
        for i in 0...3 {
            XCTAssertFalse(breaks.contains(i), "Verse line \(i) should not be a paragraph break")
        }
    }

    // MARK: - Gap-only detection (no repeated blocks)

    func testLargeGapTriggersBreak() {
        // Lines with a single large gap in the middle — should produce exactly one break
        var lines: [LyricsLine] = []
        for i in 0..<5 {
            lines.append(LyricsLine(index: i, text: "Line \(i)", timestampSeconds: Double(i) * 3.0))
        }
        // Insert a 20-second gap before line 5
        lines.append(LyricsLine(index: 5, text: "New section", timestampSeconds: 5 * 3.0 + 20.0))
        lines.append(LyricsLine(index: 6, text: "Line 6", timestampSeconds: 5 * 3.0 + 23.0))

        let breaks = computeBreaks(from: lines)
        XCTAssertTrue(breaks.contains(5), "Large-gap line should be a paragraph break")
        XCTAssertFalse(breaks.contains(0), "First line never a break")
    }
}
