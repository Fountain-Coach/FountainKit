// MetalInstrument — optional per-view MIDI 2.0 instrument runtime
// Provides per-instance CoreMIDI virtual endpoints (MIDI 2.0) and a
// lightweight vendor-JSON Property Exchange (SysEx7) to GET/SET view
// properties (e.g., rotationSpeed, zoom, tint.r/g/b).

import Foundation
import MIDI2
import MIDI2CI

#if canImport(CoreMIDI)
import CoreMIDI

public struct MetalInstrumentDescriptor: Sendable, Equatable {
    public var manufacturer: String
    public var product: String
    public var instanceId: String // GUID-like
    public var displayName: String
    public var midiGroup: UInt8
    public init(manufacturer: String, product: String, instanceId: String = UUID().uuidString, displayName: String, midiGroup: UInt8 = 0) {
        self.manufacturer = manufacturer
        self.product = product
        self.instanceId = instanceId
        self.displayName = displayName
        self.midiGroup = midiGroup
    }
}

public final class MetalInstrument: @unchecked Sendable {
    private weak var sink: MetalSceneRenderer?
    private let desc: MetalInstrumentDescriptor

    private var client: MIDIClientRef = 0
    private var src: MIDIEndpointRef = 0
    private var dest: MIDIEndpointRef = 0

    public init(sink: MetalSceneRenderer, descriptor: MetalInstrumentDescriptor) {
        self.sink = sink
        self.desc = descriptor
    }

    public func enable() {
        guard client == 0 else { return }
        let nameCF = (desc.displayName as CFString)
        let clientName = "\(desc.product)#\(desc.instanceId)" as CFString
        _ = MIDIClientCreateWithBlock(clientName, &client) { _ in }

        // Create virtual source and destination with MIDI 2.0 protocol
        MIDISourceCreateWithProtocol(client, nameCF, ._2_0, &src)
        MIDIDestinationCreateWithProtocol(client, nameCF, ._2_0, &dest, { [weak self] (list, _) in
            self?.handleEventList(list)
        })

        // Publish initial state via CI envelope (JSON payload)
        publishStateCI()
    }

    public func disable() {
        if src != 0 { MIDIEndpointDispose(src); src = 0 }
        if dest != 0 { MIDIEndpointDispose(dest); dest = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }

    private func handleEventList(_ listPtr: UnsafePointer<MIDIEventList>) {
        let list = listPtr.pointee
        var packet = list.packet
        for _ in 0..<list.numPackets {
            let count = Int(packet.wordCount)
            if count > 0 {
                // Copy words
                var words: [UInt32] = []
                withUnsafePointer(to: packet.words) { base in
                    let u32 = UnsafeRawPointer(base).assumingMemoryBound(to: UInt32.self)
                    let buf = UnsafeBufferPointer(start: u32, count: count)
                    words.append(contentsOf: buf)
                }
                handleUMP(words)
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func handleUMP(_ words: [UInt32]) {
        guard let w1 = words.first else { return }
        let mt = UInt8((w1 >> 28) & 0xF)
        switch mt {
        case 0x4: // Channel Voice 2.0
            let statusHi = UInt8((w1 >> 20) & 0xF) << 4
            let ch = UInt8((w1 >> 16) & 0xF)
            let group = UInt8((w1 >> 24) & 0xF)
            if statusHi == 0x90, words.count >= 2 { // Note On
                let note = UInt8((w1 >> 8) & 0xFF)
                let v16 = UInt16((words[1] >> 16) & 0xFFFF)
                let vel7 = UInt8((UInt32(v16) * 127) / 65535)
                sink?.noteOn(note: note, velocity: vel7, channel: ch, group: group)
            } else if statusHi == 0xB0, words.count >= 2 { // CC (32-bit => 7-bit)
                let cc = UInt8((w1 >> 8) & 0xFF)
                let value32 = words[1]
                let v7 = UInt8((Double(value32) / 4294967295.0 * 127.0).rounded())
                sink?.controlChange(controller: cc, value: v7, channel: ch, group: group)
            } else if statusHi == 0xE0, words.count >= 2 { // PB (32-bit -> 14-bit)
                let v32 = words[1]
                let v14 = UInt16((Double(v32) / 4294967295.0 * 16383.0).rounded())
                sink?.pitchBend(value14: v14, channel: ch, group: group)
            }
        case 0x3: // SysEx7 — CI envelopes + vendor JSON PE
            handleSysEx7(words)
        default:
            break
        }
    }

    // Parse SysEx7 UMP stream and handle CI Discovery + Property Exchange (spec-style via MIDI2CI helpers).
    private func handleSysEx7(_ words: [UInt32]) {
        // Reassemble payload
        var bytes: [UInt8] = []
        var i = 0
        while i + 1 < words.count {
            let w1 = words[i], w2 = words[i+1]
            guard ((w1 >> 28) & 0xF) == 0x3 else { break }
            let count = Int((w1 >> 16) & 0xF)
            let d0 = UInt8((w1 >> 8) & 0xFF)
            let d1 = UInt8(w1 & 0xFF)
            let d2 = UInt8((w2 >> 24) & 0xFF)
            let d3 = UInt8((w2 >> 16) & 0xFF)
            let d4 = UInt8((w2 >> 8) & 0xFF)
            let d5 = UInt8(w2 & 0xFF)
            let chunk = [d0, d1, d2, d3, d4, d5].prefix(count)
            bytes.append(contentsOf: chunk)
            let status = UInt8((w1 >> 20) & 0xF)
            i += 2
            if status == 0x0 || status == 0x3 { break }
        }
        guard !bytes.isEmpty else { return }
        // Parse CI envelope
        guard let env = try? MidiCiEnvelope(sysEx7Payload: bytes) else { return }
        switch env.subId2 {
        case 0x70: // Discovery Inquiry
            sendDiscoveryReply()
        case 0x7C: // Property Exchange
            handlePropertyExchange(env)
        default:
            break
        }
    }

    private func sendDiscoveryReply() {
        // Manufacturer 0x7D (dev), device family/model zero, softwareRev 0x00000001
        let muid = self.muidFromInstance()
        let body = MidiCiDiscoveryBody(
            muid: muid,
            manufacturerId: [0x7D],
            deviceFamily: 0x0000,
            deviceModel: 0x0000,
            softwareRev: 0x00000001,
            categories: .init(profiles: false, propertyExchange: true, processInquiry: false),
            maxSysEx: 4096
        )
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x71, version: 1, body: .discovery(body))
        sendSysEx7UMP(bytes: env.sysEx7Payload())
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "ci.discovery.reply"])        
    }

    private func applyProperties(_ properties: [String: Any]) {
        // Accept flat {name: float} or {properties:[{name:value},...]}
        if let props = properties["properties"] as? [[String: Any]] {
            for p in props { applyProperty(p) }
        } else {
            for (k, v) in properties { if let f = v as? Double { sink?.setUniform(k, float: Float(f)) } }
        }
    }

    private func applyProperty(_ item: [String: Any]) {
        guard let name = item["name"] as? String else { return }
        if let value = item["value"] as? Double { sink?.setUniform(name, float: Float(value)) }
    }

    func publishStateCI(requestId: UInt32? = nil) {
        // Compose property snapshot as JSON
        let snapshot: [String: Any] = [
            "identity": [
                "manufacturer": desc.manufacturer,
                "product": desc.product,
                "instanceId": desc.instanceId
            ],
            "pe": ["version": 1, "supports": ["get", "set"]]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: snapshot)) ?? Data()
        let pe = MidiCiPropertyExchangeBody(
            command: (requestId != nil ? .getReply : .notify),
            requestId: requestId ?? 0,
            encoding: .json,
            header: [:],
            data: Array(data)
        )
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        sendSysEx7UMP(bytes: env.sysEx7Payload())
    }

    private func handlePropertyExchange(_ env: MidiCiEnvelope) {
        guard case .propertyExchange(let pe) = env.body else { return }
        switch pe.command {
        case .capInquiry:
            let caps = MidiCiPropertyExchangeBody(command: .capReply, requestId: pe.requestId, encoding: .json, header: ["formats": "json"], data: [])
            let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(caps))
            sendSysEx7UMP(bytes: env.sysEx7Payload())
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "pe.capInquiry"])                
        case .get:
            publishStateCI(requestId: pe.requestId)
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "pe.get"])                
        case .set:
            // Parse JSON and apply
            if pe.encoding == .json, let dict = (try? JSONSerialization.jsonObject(with: Data(pe.data))) as? [String: Any] {
                applyProperties(dict)
            }
            // Reply with new state
            let ack = MidiCiPropertyExchangeBody(command: .setReply, requestId: pe.requestId, encoding: .json, header: [:], data: [])
            let envAck = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(ack))
            sendSysEx7UMP(bytes: envAck.sysEx7Payload())
            publishStateCI()
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "pe.set.request"])                
        default:
            // Not implemented: subscribe/notify/terminate
            let nak = MidiCiAckNakBody(ack: false, statusCode: 0x10, message: "Unsupported PE command")
            let envNak = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7F, version: 1, body: .ackNak(nak))
            sendSysEx7UMP(bytes: envNak.sysEx7Payload())
        }
    }

    private func muidFromInstance() -> UInt32 {
        // Hash instanceId to a 28-bit value (7-bit packed in SysEx7 helpers)
        var hasher = Hasher()
        hasher.combine(desc.instanceId)
        let hash = hasher.finalize()
        let raw = UInt32(truncatingIfNeeded: hash)
        return raw & 0x0FFF_FFFF
    }

    // Send SysEx7 UMP stream with correct packet headers (Single/Start/Continue/End), 6 bytes per packet
    private func buildSysEx7Words(bytes: [UInt8], group: UInt8 = 0) -> [UInt32] {
        guard client != 0, src != 0 else { return [] }
        let chunks: [[UInt8]] = stride(from: 0, to: bytes.count, by: 6).map { Array(bytes[$0..<min($0+6, bytes.count)]) }
        var words: [UInt32] = []
        for (idx, chunk) in chunks.enumerated() {
            let isSingle = chunks.count == 1
            let isFirst = idx == 0
            let isLast = idx == chunks.count - 1
            let status: UInt8 = isSingle ? 0x0 : (isFirst ? 0x1 : (isLast ? 0x3 : 0x2))
            let num = UInt8(chunk.count)
            // Build 8 bytes for two 32-bit words
            var b: [UInt8] = Array(repeating: 0, count: 8)
            b[0] = (0x3 << 4) | (group & 0xF)
            b[1] = (status << 4) | (num & 0xF)
            for i in 0..<min(6, chunk.count) { b[2 + i] = chunk[i] }
            let w1 = UInt32(bigEndian: (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3]))
            let w2 = UInt32(bigEndian: (UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7]))
            words.append(w1); words.append(w2)
        }
        return words
    }

    private func sendSysEx7UMP(bytes: [UInt8], group: UInt8 = 0) {
        let words = buildSysEx7Words(bytes: bytes, group: group)
        // Emit via virtual source
        let byteCount = MemoryLayout<MIDIEventList>.size + MemoryLayout<UInt32>.size * (max(1, words.count) - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var cur = MIDIEventListInit(listPtr, ._2_0)
        words.withUnsafeBufferPointer { buf in
            cur = MIDIEventListAdd(listPtr, byteCount, cur, 0, buf.count, buf.baseAddress!)
        }
        _ = MIDIReceivedEventList(src, listPtr)
    }

    public func sendVendorJSONEvent(topic: String, dict: [String: Any], group: UInt8 = 0) {
        // Vendor 0x7D + UTF8 JSON payload: [F0 7D 'J' 'S' 'O' 'N' 00 <json bytes> F7] (enveloped via SysEx7 UMP)
        var payload: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4F, 0x4E, 0x00]
        let body: [String: Any] = ["topic": topic, "data": dict, "ts": ISO8601DateFormatter().string(from: Date())]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        payload.append(contentsOf: data)
        payload.append(0xF7)
        let words = buildSysEx7Words(bytes: payload, group: group)
        // Send
        sendSysEx7UMP(bytes: payload, group: group)
        // Publish for recorders
        NotificationCenter.default.post(name: .MetalCanvasUMPOut, object: nil, userInfo: ["topic": topic, "data": body, "words": words])
    }
}

#endif
