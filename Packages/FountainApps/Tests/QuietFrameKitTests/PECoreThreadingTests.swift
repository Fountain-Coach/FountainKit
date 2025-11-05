import XCTest
import MIDI2CI
@testable import QuietFrameKit

final class PECoreThreadingTests: XCTestCase {
    final class Delegate: QFPECoreDelegate {
        let expUpdate: XCTestExpectation
        let expEvent: XCTestExpectation
        init(_ u: XCTestExpectation, _ e: XCTestExpectation) { expUpdate = u; expEvent = e }
        func peDidUpdateSnapshot(json: String) {
            XCTAssertTrue(Thread.isMainThread, "Delegate must be called on main thread/@MainActor")
            XCTAssert(json.contains("properties") || json.contains("identity"))
            expUpdate.fulfill()
        }
        func peDidEmitUMPEvent(json: String) {
            XCTAssertTrue(Thread.isMainThread, "Delegate must be called on main thread/@MainActor")
            XCTAssert(json.contains("ump"))
            expEvent.fulfill()
        }
    }

    func testPENotify_MarshalsToMainActor() throws {
        let core = QFPEClientCore()
        let u = expectation(description: "snapshot")
        let e = expectation(description: "event")
        let del = Delegate(u, e)
        core.delegate = del

        // Compose a minimal PE notify with properties JSON
        let snapshot: [String: Any] = [
            "identity": ["manufacturer": "Fountain", "product": "QuietFrame", "instanceId": "test"],
            "properties": ["engine.masterGain": 0.8]
        ]
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let pe = MidiCiPropertyExchangeBody(command: .notify, requestId: 0, encoding: .json, header: [:], data: Array(data))
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        let bytes = env.sysEx7Payload()
        let words = QFUMP.packSysEx7(bytes)

        // Feed from a background queue to mirror CoreMIDI callback context
        let q = DispatchQueue(label: "test.pecore.bg")
        q.async {
            core.handleSysEx7UMP(words: words)
        }

        wait(for: [u, e], timeout: 2.0)
    }
}

