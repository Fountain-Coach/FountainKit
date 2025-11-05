import XCTest
@testable import MetalViewKit
import MIDI2CI
import MIDI2Transports

final class RTPIntegrationTests: XCTestCase {
    func testPEGetRoundTripOverRTP() throws {
        // Use a high, unlikely port
        let port: UInt16 = 5868
        MetalInstrument.setTransportOverride(MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(port)))

        let sink = DummySink()
        let inst = MetalInstrument(sink: sink, descriptor: .init(manufacturer: "Fountain", product: "QF-RTPTarget", displayName: "QF-RTP"))
        inst.stateProvider = { ["engine.masterGain": 0.25] }
        inst.enable()

        // Client
        let client = RTPMidiSession(localName: "QF-Client", mtu: 1400, enableDiscovery: false, enableCINegotiation: true, listenPort: nil)
        try client.open()
        try client.connect(host: "127.0.0.1", port: port)

        let gotReply = expectation(description: "got PE reply")
        client.onReceiveUMP = { words in
            // SysEx7 → CI envelope
            var bytes: [UInt8] = []
            var i = 0
            while i + 1 < words.count {
                let w1 = words[i], w2 = words[i+1]
                if ((w1 >> 28) & 0xF) != 0x3 { break }
                let n = Int((w1 >> 16) & 0xF)
                let d0 = UInt8((w1 >> 8) & 0xFF)
                let d1 = UInt8(w1 & 0xFF)
                let d2 = UInt8((w2 >> 24) & 0xFF)
                let d3 = UInt8((w2 >> 16) & 0xFF)
                let d4 = UInt8((w2 >> 8) & 0xFF)
                let d5 = UInt8(w2 & 0xFF)
                bytes.append(contentsOf: [d0,d1,d2,d3,d4,d5].prefix(n))
                let status = UInt8((w1 >> 20) & 0xF)
                i += 2
                if status == 0x0 || status == 0x3 { break }
            }
            // Accept both raw and payload-only
            var payload = bytes
            if bytes.first == 0xF0, bytes.last == 0xF7, bytes.count > 2 { payload = Array(bytes.dropFirst().dropLast()) }
            if let env = try? MidiCiEnvelope(sysEx7Payload: payload), case .propertyExchange(let pe) = env.body {
                if pe.command == .getReply || pe.command == .notify { gotReply.fulfill() }
            }
        }

        // Send GET
        let pe = MidiCiPropertyExchangeBody(command: .get, requestId: 42, encoding: .json, header: [:], data: [])
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        let payload = env.sysEx7Payload()
        var words: [UInt32] = []
        var idx = 0
        while idx < payload.count {
            let remain = payload.count - idx
            let n = min(6, remain)
            let status: UInt8 = (idx == 0 ? (n == remain ? 0x0 : 0x2) : (n == remain ? 0x3 : 0x1))
            var b = Array(payload[idx..<(idx+n)])
            while b.count < 6 { b.append(0) }
            let w1 = (UInt32(0x3) << 28) | (0 << 24) | (UInt32(status) << 20) | (UInt32(n) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(contentsOf: [w1, w2])
            idx += n
        }
        try client.send(umps: [words])
        wait(for: [gotReply], timeout: 2.0)
    }
}

private final class DummySink: MetalSceneRenderer {
    func setUniform(_ name: String, float: Float) {}
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
}

