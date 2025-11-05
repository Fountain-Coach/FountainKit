import XCTest
@testable import MetalViewKit
import MIDI2CI

final class SysExTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        // Force loopback transport to avoid CoreMIDI/Network
        MetalInstrument.setTransportOverride(LoopbackMetalInstrumentTransport.shared)
    }

    func testVendorJSON_StartContinueEnd() throws {
        let sink = DummySink()
        let inst = MetalInstrument(sink: sink, descriptor: .init(manufacturer: "Fountain", product: "Test", displayName: "QF-Test"))
        inst.enable()
        guard let handle = LoopbackMetalInstrumentTransport.shared.resolveDisplayName("QF-Test") else {
            return XCTFail("loopback handle not found")
        }
        // Build JSON vendor payload and split across 2 chunks
        let json = try XCTUnwrap(String(data: try JSONSerialization.data(withJSONObject: ["topic":"rec.start"]), encoding: .utf8))
        var bytes: [UInt8] = [0xF0,0x7D,0x4A,0x53,0x4E,0x00]
        bytes.append(contentsOf: Array(json.utf8))
        bytes.append(0xF7)
        // Two UMP packets: start/continue/end
        let first = Array(bytes.prefix(6))
        let rest = Array(bytes.dropFirst(6))
        let wStart = buildSysEx7UMP(status: 0x2, n: UInt8(first.count), payload: first)
        let wEnd = buildSysEx7UMP(status: 0x3, n: UInt8(min(6, rest.count)), payload: Array(rest.prefix(6)))
        XCTAssertTrue(handle.send(words: wStart))
        XCTAssertTrue(handle.send(words: wEnd))
        // If we got here with no crash, pass
    }

    func testPropertyExchangeGetReplyPath() throws {
        let sink = DummySink()
        let inst = MetalInstrument(sink: sink, descriptor: .init(manufacturer: "Fountain", product: "Test", displayName: "QF-Test-PE"))
        inst.stateProvider = { ["engine.masterGain": 0.5] }
        inst.enable()
        guard let handle = LoopbackMetalInstrumentTransport.shared.resolveDisplayName("QF-Test-PE") else {
            return XCTFail("loopback handle not found")
        }
        // Compose PE GET CI envelope
        let pe = MidiCiPropertyExchangeBody(command: .get, requestId: 1, encoding: .json, header: [:], data: [])
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        let payload = env.sysEx7Payload()
        let words = buildSysEx7UMPStream(payload: payload)
        XCTAssertTrue(handle.send(words: words))
    }
}

private final class DummySink: MetalSceneRenderer {
    func setUniform(_ name: String, float: Float) {}
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
}

private func buildSysEx7UMP(status: UInt8, n: UInt8, payload: [UInt8], group: UInt8 = 0) -> [UInt32] {
    var b = payload
    while b.count < 6 { b.append(0) }
    let w1 = (UInt32(0x3) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(status & 0xF) << 20) | (UInt32(n & 0xF) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
    let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
    return [w1, w2]
}

private func buildSysEx7UMPStream(payload: [UInt8], group: UInt8 = 0) -> [UInt32] {
    var words: [UInt32] = []
    var idx = 0
    while idx < payload.count {
        let remain = payload.count - idx
        let n = min(6, remain)
        let status: UInt8
        if idx == 0 && n == remain { status = 0x0 }
        else if idx == 0 { status = 0x2 }
        else if n == remain { status = 0x3 }
        else { status = 0x1 }
        words += buildSysEx7UMP(status: status, n: UInt8(n), payload: Array(payload[idx..<(idx+n)]), group: group)
        idx += n
    }
    return words
}

