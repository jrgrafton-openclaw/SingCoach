import XCTest
@testable import SingCoach

final class ToneGeneratorServiceTests: XCTestCase {
    
    // MARK: - Math helpers (pure static, no AVAudio, no @MainActor needed)
    
    func testFrequencyCalculation() {
        XCTAssertEqual(ToneGeneratorService.frequency(for: 69), 440.0, accuracy: 0.01)
        XCTAssertEqual(ToneGeneratorService.frequency(for: 60), 261.63, accuracy: 0.01)
        XCTAssertEqual(ToneGeneratorService.frequency(for: 72), 523.25, accuracy: 0.01)
        XCTAssertEqual(ToneGeneratorService.frequency(for: 36), 65.41, accuracy: 0.01)
    }
    
    func testNoteNameFromMidi() {
        XCTAssertEqual(ToneGeneratorService.noteName(for: 60), "C4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 69), "A4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 72), "C5")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 36), "C2")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 67), "G4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 64), "E4")
    }
    
    func testNoteNameFromFrequency() {
        // Call the frequency: Double overload explicitly
        XCTAssertEqual(ToneGeneratorService.noteName(for: 440.0 as Double), "A4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 261.63 as Double), "C4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 523.25 as Double), "C5")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 0.0 as Double), "--")
        XCTAssertEqual(ToneGeneratorService.noteName(for: -100.0 as Double), "--")
    }
    
    func testMidiRange() {
        XCTAssertEqual(ToneGeneratorService.midiRange.lowerBound, 36) // C2
        XCTAssertEqual(ToneGeneratorService.midiRange.upperBound, 72) // C5
    }
    
    func testAllMidiRangeNotesHaveValidFrequency() {
        for midi in 36...72 {
            let freq = ToneGeneratorService.frequency(for: midi)
            XCTAssertGreaterThan(freq, 0, "MIDI \(midi) should have positive frequency")
            XCTAssertLessThan(freq, 20000, "MIDI \(midi) frequency should be audible")
        }
    }
    
    func testAllMidiRangeNotesHaveValidNoteNames() {
        let validNotes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        for midi in 36...72 {
            let name = ToneGeneratorService.noteName(for: midi)
            let prefix = String(name.prefix(while: { !$0.isNumber && $0 != "-" }))
            XCTAssertTrue(validNotes.contains(prefix), "MIDI \(midi) note name '\(name)' has invalid prefix")
        }
    }
    
    // MARK: - Lifecycle tests (run on @MainActor via MainActor.run)
    
    /// Calling stop() before ever calling play() must not crash
    func testStopBeforePlayDoesNotCrash() async {
        await MainActor.run {
            let sut = ToneGeneratorService()
            XCTAssertFalse(sut.isPlaying)
            sut.stop()
            XCTAssertFalse(sut.isPlaying)
        }
    }
    
    /// Calling stop() twice must not crash
    func testDoubleStopDoesNotCrash() async {
        await MainActor.run {
            let sut = ToneGeneratorService()
            sut.stop()
            sut.stop()
            XCTAssertFalse(sut.isPlaying)
        }
    }
    
    /// play() followed immediately by stop() must not crash (crashes the engine tear-down race)
    func testPlayThenImmediateStopDoesNotCrash() async {
        await MainActor.run {
            let sut = ToneGeneratorService()
            sut.play(midiNote: 69) // A4
            sut.stop()             // Immediate — must not crash
            XCTAssertFalse(sut.isPlaying)
        }
    }
    
    /// Rapidly calling play() multiple times must not crash (tests engine tear-down / re-create path)
    func testRapidPlayDoesNotCrash() async throws {
        await MainActor.run {
            let sut = ToneGeneratorService()
            for midiNote in [60, 64, 67, 69, 72] {
                sut.play(midiNote: midiNote)
            }
            sut.stop()
            XCTAssertFalse(sut.isPlaying)
        }
        // Brief pause to let any deferred audio callbacks settle
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    /// Deallocating ToneGeneratorService while auto-stop timer is pending must not crash
    func testDeallocWhilePlayingDoesNotCrash() async throws {
        await MainActor.run {
            var sut: ToneGeneratorService? = ToneGeneratorService()
            sut?.play(midiNote: 69)
            sut = nil  // Dealloc with pending auto-stop Task — must not crash
        }
        // Let any in-flight async work settle
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}
