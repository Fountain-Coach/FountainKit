import XCTest
@testable import quietframe_companion_app
import MIDI2CI

final class ThreadingTests: XCTestCase {
    func testEventSinkRunsOnMainActor() async {
        let client = QuietFramePEClient()
        let exp = expectation(description: "eventSink main thread")
        client.eventSink = { _ in
            XCTAssertTrue(Thread.isMainThread, "eventSink must be on main thread")
            exp.fulfill()
        }
        // Build a minimal SysEx7 UMP payload and feed inbound path
        let payload = Data([0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00, 0x7D, 0xF7])
        let words = Self.sysEx7ToUMP(Array(payload))
        client.test_handleUMPWords(words)
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testSnapshotUpdatedOnMainActor() async {
        let client = QuietFramePEClient()
        let exp = expectation(description: "snapshot updated")
        // Compose a PE notify with JSON {"properties":[]}
        let notify = MidiCiPropertyExchangeBody(command: .notify, requestId: 1, encoding: .json, header: [:], data: Array("{\"properties\":[]}".utf8))
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(notify))
        let bytes = env.sysEx7Payload()
        let words = Self.sysEx7ToUMP(bytes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            client.test_handleUMPWords(words)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !client.lastSnapshotJSON.isEmpty { exp.fulfill() }
        }
        await fulfillment(of: [exp], timeout: 1.0)
    }

    private static func sysEx7ToUMP(_ bytes: [UInt8]) -> [UInt32] {
        var words: [UInt32] = []
        var idx = 0
        while idx < bytes.count {
            let remain = bytes.count - idx
            let n = min(6, remain)
            let status: UInt8
            if idx == 0 && n == remain { status = 0x0 }
            else if idx == 0 { status = 0x2 }
            else if n == remain { status = 0x3 }
            else { status = 0x1 }
            var b = Array(bytes[idx..<(idx+n)])
            while b.count < 6 { b.append(0) }
            let w1 = (UInt32(0x3) << 28) | (UInt32(0) << 24) | (UInt32(status) << 20) | (UInt32(n) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(w1); words.append(w2)
            idx += n
        }
        return words
    }
}

