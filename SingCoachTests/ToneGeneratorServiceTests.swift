import XCTest
@testable import SingCoach

final class ToneGeneratorServiceTests: XCTestCase {
    
    func testFrequencyCalculation() {
        // A4 = 440 Hz at MIDI note 69
        XCTAssertEqual(ToneGeneratorService.frequency(for: 69), 440.0, accuracy: 0.01)
        
        // C4 = MIDI 60 should be ~261.63 Hz
        XCTAssertEqual(ToneGeneratorService.frequency(for: 60), 261.63, accuracy: 0.01)
        
        // C5 = MIDI 72 should be ~523.25 Hz
        XCTAssertEqual(ToneGeneratorService.frequency(for: 72), 523.25, accuracy: 0.01)
        
        // C2 = MIDI 36 should be ~65.41 Hz
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
        // Test with known frequencies
        XCTAssertEqual(ToneGeneratorService.noteName(for: 440.0), "A4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 261.63), "C4")
        XCTAssertEqual(ToneGeneratorService.noteName(for: 523.25), "C5")
        
        // Edge case: zero frequency
        XCTAssertEqual(ToneGeneratorService.noteName(for: 0), "--")
        
        // Negative frequency
        XCTAssertEqual(ToneGeneratorService.noteName(for: -100), "--")
    }
    
    func testMidiRange() {
        // Verify the MIDI range constant
        XCTAssertEqual(ToneGeneratorService.midiRange.lowerBound, 36) // C2
        XCTAssertEqual(ToneGeneratorService.midiRange.upperBound, 72) // C5
    }
}
