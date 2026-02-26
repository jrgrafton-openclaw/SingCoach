import XCTest
@testable import SingCoach

final class PitchDetectionServiceTests: XCTestCase {
    
    // Test note name calculation from frequency (similar logic to what PitchDetectionService uses)
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    private func noteName(for frequency: Double) -> String {
        guard frequency > 0 else { return "--" }
        let midiNote = Int(round(69 + 12 * log2(frequency / 440.0)))
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    private func frequency(for midiNote: Int) -> Double {
        return 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
    
    private func centsDeviation(frequency: Double, from midiNote: Int) -> Double {
        let perfectFreq = frequency(for: midiNote)
        return 1200 * log2(frequency / perfectFreq)
    }
    
    func testNoteNameFromFrequency() {
        XCTAssertEqual(noteName(for: 440.0), "A4")
        XCTAssertEqual(noteName(for: 261.63), "C4")
        XCTAssertEqual(noteName(for: 523.25), "C5")
    }
    
    func testCentsCalculation() {
        // Perfect A4 (440 Hz) should have 0 cents deviation
        let centsA4 = centsDeviation(frequency: 440.0, from: 69)
        XCTAssertEqual(centsA4, 0.0, accuracy: 0.01)
        
        // Slightly sharp A4 (445 Hz)
        let centsSharp = centsDeviation(frequency: 445.0, from: 69)
        XCTAssertEqual(centsSharp, 19.56, accuracy: 0.1) // ~+20 cents
        
        // Slightly flat A4 (435 Hz)
        let centsFlat = centsDeviation(frequency: 435.0, from: 69)
        XCTAssertEqual(centsFlat, -19.61, accuracy: 0.1) // ~-20 cents
        
        // Perfect C4 (261.63 Hz)
        let centsC4 = centsDeviation(frequency: 261.63, from: 60)
        XCTAssertEqual(centsC4, 0.0, accuracy: 0.01)
    }
    
    func testIsInTune() {
        // In tune: within ±10 cents
        XCTAssertTrue(abs(centsDeviation(frequency: 440.0, from: 69)) <= 10)
        XCTAssertTrue(abs(centsDeviation(frequency: 442.0, from: 69)) <= 10)
        XCTAssertTrue(abs(centsDeviation(frequency: 438.0, from: 69)) <= 10)
        
        // Out of tune: more than ±10 cents
        XCTAssertFalse(abs(centsDeviation(frequency: 450.0, from: 69)) <= 10)
        XCTAssertFalse(abs(centsDeviation(frequency: 430.0, from: 69)) <= 10)
    }
    
    func testVoiceRange() {
        // Test that common singing frequencies are detected correctly
        // Bass: E2 = 82.41 Hz
        XCTAssertEqual(noteName(for: 82.41), "E2")
        
        // Tenor: A3 = 220 Hz
        XCTAssertEqual(noteName(for: 220.0), "A3")
        
        // Alto: F4 = 349.23 Hz
        XCTAssertEqual(noteName(for: 349.23), "F4")
        
        // Soprano: C6 = 1046.50 Hz
        XCTAssertEqual(noteName(for: 1046.50), "C6")
    }
}
