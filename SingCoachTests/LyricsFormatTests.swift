import XCTest
@testable import SingCoach

// Build 9: Lyrics paragraph break verification tests
@MainActor
final class LyricsFormatTests: XCTestCase {

    func testLyricsParagraphBreaks() {
        // LRC with empty-text timestamp (paragraph break marker)
        let sampleLRC = """
[00:01.00]Line one
[00:02.00]Line two
[00:03.00]
[00:04.00]Line three new paragraph
[00:05.00]Line four
"""
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics(sampleLRC)

        // Should produce 4 lines (empty-text timestamp is NOT added as a line)
        XCTAssertEqual(lines.count, 4, "Should have 4 non-empty lines; empty timestamp should be consumed as paragraph break")
        XCTAssertEqual(lines[0].text, "Line one")
        XCTAssertEqual(lines[1].text, "Line two")
        XCTAssertEqual(lines[2].text, "Line three new paragraph")
        XCTAssertEqual(lines[2].section, "¶", "Line after empty timestamp should be marked as new paragraph (section == '¶')")
        XCTAssertEqual(lines[3].text, "Line four")
        XCTAssertNil(lines[3].section, "Fourth line should NOT be marked as paragraph break")
    }

    func testPlainLyricsParagraphBreaks() {
        let plainLyrics = "Line one\nLine two\n\nLine three\nLine four"
        let service = LRCLibService.shared
        let lines = service.parsePlainLyrics(plainLyrics)

        XCTAssertEqual(lines.count, 4, "Should have 4 lines; blank line becomes paragraph break marker")
        XCTAssertEqual(lines[0].text, "Line one")
        XCTAssertEqual(lines[1].text, "Line two")
        XCTAssertEqual(lines[2].text, "Line three")
        XCTAssertEqual(lines[2].section, "¶", "First line after blank should be marked as paragraph break")
        XCTAssertNil(lines[3].section, "Subsequent line in same paragraph should not be marked")
    }

    func testLRCParagraphBreakOnlyMarksFirstLineAfterBreak() {
        // Multiple blank lines should only mark the FIRST line of the next paragraph
        let lrc = """
[00:01.00]A
[00:02.00]B

[00:03.00]C
[00:04.00]D
"""
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics(lrc)

        XCTAssertEqual(lines.count, 4)
        XCTAssertNil(lines[0].section)
        XCTAssertNil(lines[1].section)
        XCTAssertEqual(lines[2].section, "¶")
        XCTAssertNil(lines[3].section)
    }

    func testFirstLinesNeverMarkedAsParagraphBreak() {
        // The very first line should never get a paragraph break marker
        let lrc = "[00:01.00]First line\n[00:02.00]Second line"
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics(lrc)
        XCTAssertNil(lines[0].section, "First line should never be marked as paragraph break")
    }

    func testNamedSectionHeaderInLRC() {
        // Lines like "[verse]" or "[chorus]" in LRC should be treated as section markers
        // (handled by the metadata skip path with pendingNewParagraph = true)
        let lrc = """
[00:01.00]Line one
[chorus]
[00:02.00]Line two chorus
"""
        let service = LRCLibService.shared
        let lines = service.parseLRCLyrics(lrc)
        // [chorus] is a metadata line, should cause next line to get a paragraph/section break
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotNil(lines[1].section, "Line after metadata/section marker should have a section set")
    }
}
