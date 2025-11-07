import XCTest
@testable import QuietFrameKit
import MIDI2
import MIDI2CI

final class MidiCISafeParserTests: XCTestCase {
    func testVendorJSNIsNotMidiCI() throws {
        var bytes: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00]
        bytes.append(contentsOf: Array("{\"topic\":\"t\"}".utf8))
        bytes.append(0xF7)
        XCTAssertNil(SafeMidiCI.decode(sysEx7: bytes))
    }

    func testValidMidiCIEncDec() throws {
        let pe = MidiCiPropertyExchangeBody(command: .notify, requestId: 1, encoding: .json, header: [:], data: Array("{}".utf8))
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x70, version: 1, body: .propertyExchange(pe))
        let bytes = env.sysEx7Payload()
        let parsed = SafeMidiCI.decode(sysEx7: bytes)
        XCTAssertNotNil(parsed)
    }

    func testTruncatedIsRejected() throws {
        let bad: [UInt8] = [0xF0, 0x7E, 0x7F, 0x0D, 0x70] // no F7
        XCTAssertNil(SafeMidiCI.decode(sysEx7: bad))
    }

    func testWrongManufacturerIsRejected() throws {
        let bad: [UInt8] = [0xF0, 0x7D, 0x00, 0x0D, 0x70, 0x00, 0xF7]
        XCTAssertNil(SafeMidiCI.decode(sysEx7: bad))
    }
}
