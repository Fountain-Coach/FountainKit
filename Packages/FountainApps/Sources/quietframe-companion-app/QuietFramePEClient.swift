import Foundation
import CoreMIDI
import MIDI2
import MIDI2CI

@MainActor final class QuietFramePEClient: ObservableObject {
    @Published var connectedName: String? = nil
    @Published var lastSnapshotJSON: String = ""

    private var client: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var dest: MIDIEndpointRef = 0
    private var src: MIDIEndpointRef = 0
    private var inPort: MIDIPortRef = 0
    private let group: UInt8 = 0
    private var requestId: UInt32 = 1

    func connect(displayNameContains name: String = "Quiet Frame") {
        if client == 0 { MIDIClientCreate("QFCompanion" as CFString, nil, nil, &client) }
        if outPort == 0 { MIDIOutputPortCreate(client, "out" as CFString, &outPort) }
        if inPort == 0 {
            if #available(macOS 13.0, *) {
                MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._2_0, &inPort) { [weak self] list, _ in
                    self?.onEventList(list)
                }
            }
        }
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let d = MIDIGetDestination(i)
            var cf: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(d, kMIDIPropertyDisplayName, &cf) == noErr {
                let n = cf?.takeRetainedValue() as String? ?? ""
                if n.localizedCaseInsensitiveContains(name) {
                    dest = d
                    connectedName = n
                    break
                }
            }
        }
        let scount = MIDIGetNumberOfSources()
        for i in 0..<scount {
            let s = MIDIGetSource(i)
            var cf: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(s, kMIDIPropertyDisplayName, &cf) == noErr {
                let n = cf?.takeRetainedValue() as String? ?? ""
                if n.localizedCaseInsensitiveContains(name) {
                    src = s
                    if inPort != 0 { MIDIPortConnectSource(inPort, src, nil) }
                    break
                }
            }
        }
    }

    func get() {
        guard dest != 0 else { return }
        let pe = MidiCiPropertyExchangeBody(command: .get, requestId: requestId, encoding: .json, header: [:], data: [])
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        sendSysEx7(bytes: env.sysEx7Payload())
        requestId &+= 1
    }

    func set(_ pairs: [(String, Double)]) {
        guard dest != 0 else { return }
        let props = pairs.map { ["name": $0.0, "value": $0.1] }
        let obj: [String: Any] = ["properties": props]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let pe = MidiCiPropertyExchangeBody(command: .set, requestId: requestId, encoding: .json, header: [:], data: Array(data))
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        sendSysEx7(bytes: env.sysEx7Payload())
        requestId &+= 1
    }

    private func sendSysEx7(bytes: [UInt8]) {
        var words: [UInt32] = []
        var idx = 0
        let total = bytes.count
        while idx < total {
            let remain = total - idx
            let n = min(remain, 6)
            let status: UInt8
            if idx == 0 && n == remain { status = 0x0 } // complete
            else if idx == 0 { status = 0x2 } // start
            else if n == remain { status = 0x3 } // end
            else { status = 0x1 } // continue
            var b: [UInt8] = Array(bytes[idx..<(idx+n)])
            while b.count < 6 { b.append(0) }
            let w1 = (UInt32(0x3) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(status & 0xF) << 20) | (UInt32(n & 0xF) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(w1); words.append(w2)
            idx += n
        }
        sendUMP(words: words)
    }

    private func sendUMP(words: [UInt32]) {
        var listLen = MemoryLayout<MIDIEventList>.size + MemoryLayout<UInt32>.size * max(0, words.count - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: listLen, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var cur = MIDIEventListInit(listPtr, ._2_0)
        words.withUnsafeBufferPointer { buf in
            cur = MIDIEventListAdd(listPtr, listLen, cur, 0, buf.count, buf.baseAddress!)
        }
        MIDISendEventList(outPort, dest, listPtr)
    }
}

// MARK: - Inbound handling
extension QuietFramePEClient {
    private func onEventList(_ listPtr: UnsafePointer<MIDIEventList>) {
        var packet = listPtr.pointee.packet
        for _ in 0..<listPtr.pointee.numPackets {
            let count = Int(packet.wordCount)
            if count > 0 {
                var words: [UInt32] = []
                withUnsafePointer(to: packet.words) { base in
                    let raw = UnsafeRawPointer(base).assumingMemoryBound(to: UInt32.self)
                    let buffer = UnsafeBufferPointer(start: raw, count: count)
                    words.append(contentsOf: buffer)
                }
                handleWords(words)
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func handleWords(_ words: [UInt32]) {
        // SysEx7 only for now
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
        guard !bytes.isEmpty else { return }
        if let env = try? MidiCiEnvelope(sysEx7Payload: bytes) {
            if case .propertyExchange(let pe) = env.body {
                if pe.command == .getReply || pe.command == .notify {
                    if let obj = try? JSONSerialization.jsonObject(with: Data(pe.data)) as? [String: Any] {
                        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]), let s = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async { self.lastSnapshotJSON = s }
                        }
                    }
                }
            }
        }
    }
}
