import XCTest
@testable import MIDI2Transports

final class BLEParseTests: XCTestCase {
    func testParseNoteOnOff() throws {
        // BLE MIDI: [timestamp][status][d1][d2] ... timestamps 0x80..0xBF
        // Build: timestamp 0x80, NoteOn ch0 (0x90), note 60, vel 100; then timestamp, NoteOff
        let data = Data([0x80, 0x90, 60, 100, 0x80, 0x80, 60, 0x00])
        let msgs = BLEMidiTransport.parseBLEMidiStream(data)
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0], [0x90, 60, 100])
        XCTAssertEqual(msgs[1], [0x80, 60, 0x00])

        // Map to UMP (MIDI 1.0 message type)
        func toUMP(_ m: [UInt8]) -> UInt32 {
            let status = m[0], d1 = m.count > 1 ? m[1] : 0, d2 = m.count > 2 ? m[2] : 0
            return (UInt32(0x2) << 28) | (0 << 24) | (UInt32(status) << 16) | (UInt32(d1) << 8) | UInt32(d2)
        }
        let umps = msgs.map(toUMP)
        XCTAssertEqual(umps[0] >> 28, 0x2)
        XCTAssertEqual((umps[0] >> 16) & 0xFF, 0x90)
        XCTAssertEqual((umps[0] >> 8) & 0xFF, 60)
        XCTAssertEqual(umps[0] & 0xFF, 100)
    }
}

