import XCTest
@testable import QuietFrameKit

final class UMPTests: XCTestCase {
    func roundTrip(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        let words = QFUMP.packSysEx7(bytes)
        let out = QFUMP.unpackSysEx7(words: words)
        XCTAssertEqual(out, bytes, file: file, line: line)
    }

    func testPackUnpack_ShortLengths() {
        roundTrip([0xF0, 0x01, 0xF7])
        roundTrip([0xF0, 0x7D, 0xF7])
        roundTrip([0xF0, 0x7D, 0x01, 0xF7])
        roundTrip([0xF0, 0x7D, 0x01, 0x02, 0xF7])
        roundTrip([0xF0, 0x7D, 0x01, 0x02, 0x03, 0xF7])
        roundTrip([0xF0, 0x7D, 0x01, 0x02, 0x03, 0x04, 0xF7])
    }

    func testPackUnpack_MultiChunks() {
        // 12-byte payload across two UMP packets
        var bytes: [UInt8] = [0xF0, 0x7D]
        bytes.append(contentsOf: Array(repeating: 0x55, count: 10))
        bytes.append(0xF7)
        roundTrip(bytes)
    }
}

