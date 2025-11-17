import XCTest
@testable import mpe_pad_app

final class MPEPadMappingTests: XCTestCase {
    func testCenterPitchBendIs8192() {
        let pb = MPEPadMapping.pitchBend14(x: 0.5)
        XCTAssertEqual(pb, 8192, "Center should map to 8192")
    }
    func testBoundsPitchBend() {
        XCTAssertEqual(MPEPadMapping.pitchBend14(x: 0.0), 0)
        XCTAssertEqual(MPEPadMapping.pitchBend14(x: 1.0), 16383)
    }
    func testMonotonicPitchBend() {
        var prev: UInt16 = 0
        for i in 0...100 { let x = Double(i)/100.0; let v = MPEPadMapping.pitchBend14(x: x); XCTAssertGreaterThanOrEqual(v, prev); prev = v }
    }
    func testVelocityRange() {
        XCTAssertGreaterThanOrEqual(MPEPadMapping.velocity(y: 0.0), 20)
        XCTAssertLessThanOrEqual(MPEPadMapping.velocity(y: 1.0), 127)
    }
    func testRPNSequence() {
        let seq = MPEPadMapping.rpnPitchBendSensitivity(semitones: 48)
        XCTAssertEqual(seq.count, 6)
        XCTAssertEqual(seq[0].0, 101); XCTAssertEqual(seq[0].1, 0)
        XCTAssertEqual(seq[1].0, 100); XCTAssertEqual(seq[1].1, 0)
        XCTAssertEqual(seq[2].0, 6)
        XCTAssertEqual(seq[3].0, 38)
        XCTAssertEqual(seq[4].0, 101); XCTAssertEqual(seq[4].1, 127)
        XCTAssertEqual(seq[5].0, 100); XCTAssertEqual(seq[5].1, 127)
    }
}

