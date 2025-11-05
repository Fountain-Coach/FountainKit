// MetalInstrument — optional per-view MIDI 2.0 instrument runtime
// Provides per-instance CoreMIDI virtual endpoints (MIDI 2.0) and a
// lightweight vendor-JSON Property Exchange (SysEx7) to GET/SET view
// properties (e.g., rotationSpeed, zoom, tint.r/g/b).

import Foundation
import MIDI2
import MIDI2CI

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
    public var stateProvider: (() -> [String: Any])? = nil

    private let transport: any MetalInstrumentTransport
    private var session: (any MetalInstrumentTransportSession)?
    private static let transportHolder = TransportHolder(defaultTransport: MetalInstrument.makeSystemDefaultTransport())
    private static let enableQueue = DispatchQueue(label: "MetalInstrument.enable", qos: .userInitiated)
    private static let enableTimeout: TimeInterval = 2.0
    private var enableToken: UUID?

    public init(sink: MetalSceneRenderer,
                descriptor: MetalInstrumentDescriptor,
                transport: (any MetalInstrumentTransport)? = nil) {
        self.sink = sink
        self.desc = descriptor
        self.transport = transport ?? MetalInstrument.defaultTransport()
    }

    public func enable() {
        guard session == nil else { return }
        let token = UUID()
        enableToken = token
        let descriptor = desc
        MetalInstrument.enableQueue.async { [weak self] in
            guard let self else { return }
            do {
                let newSession = try self.transport.makeSession(descriptor: descriptor) { [weak self] words in
                    self?.handleUMP(words)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        newSession.close()
                        return
                    }
                    guard self.enableToken == token else {
                        newSession.close()
                        return
                    }
                    self.session = newSession
                    self.enableToken = nil
                    self.publishStateCI()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.handleEnableFailure(token: token, message: "Transport setup failed", error: error)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MetalInstrument.enableTimeout) { [weak self] in
            guard let self else { return }
            if self.enableToken == token, self.session == nil {
                self.handleEnableFailure(token: token, message: "Transport setup timed out", error: nil)
            }
        }
    }

    public func disable() {
        enableToken = nil
        session?.close()
        session = nil
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
        // Vendor JSON payload: F0 7D 'JSON' 00 <utf8 json> F7
        if bytes.count >= 8, bytes[0] == 0xF0, bytes[1] == 0x7D,
           bytes[2] == 0x4A, bytes[3] == 0x53, bytes[4] == 0x4F, bytes[5] == 0x4E, bytes[6] == 0x00 {
            let body = Data(bytes[7..<(bytes.count-1)]) // strip F7
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                handleVendorJSON(obj)
            }
            return
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

    private func handleVendorJSON(_ obj: [String: Any]) {
        guard let topic = obj["topic"] as? String else { return }
        let data = (obj["data"] as? [String: Any]) ?? [:]
        switch topic {
        case "rec.start":
            NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordCommand"), object: nil, userInfo: ["op": "start"])
        case "rec.stop":
            NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordCommand"), object: nil, userInfo: ["op": "stop"])
        case "ui.zoomAround":
            let ax = CGFloat((data["anchor.view.x"] as? Double) ?? 0)
            let ay = CGFloat((data["anchor.view.y"] as? Double) ?? 0)
            let mag = CGFloat((data["magnification"] as? Double) ?? 0)
            NotificationCenter.default.post(name: Notification.Name("MetalCanvasRendererCommand"), object: nil, userInfo: ["op": "zoomAround", "anchor.x": ax, "anchor.y": ay, "magnification": mag])
            // Emit a matching monitor activity event so tests observing only monitor traffic see it deterministically
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "ui.zoom.debug",
                "anchor.view.x": Double(ax),
                "anchor.view.y": Double(ay),
                "magnification": Double(mag)
            ])
        case "ui.panBy":
            // Resolve current zoom/translation from state provider (renderer snapshot)
            var z: Double = 1.0
            var txCur: Double = 0.0
            var tyCur: Double = 0.0
            if let props = stateProvider?() {
                if let zoom = props["zoom"] as? Double { z = max(0.0001, zoom) }
                else if let zoomNum = props["zoom"] as? NSNumber { z = max(0.0001, zoomNum.doubleValue) }
                if let tx = props["translation.x"] as? Double { txCur = tx }
                if let ty = props["translation.y"] as? Double { tyCur = ty }
            }
            if let dx = data["dx.doc"] as? Double, let dy = data["dy.doc"] as? Double {
                // Apply directly via sink uniforms to ensure transform-change notifications
                sink?.setUniform("translation.x", float: Float(txCur + dx))
                sink?.setUniform("translation.y", float: Float(tyCur + dy))
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type": "ui.pan.debug",
                    "dx.doc": dx,
                    "dy.doc": dy
                ])
            } else if let vx = data["dx.view"] as? Double, let vy = data["dy.view"] as? Double {
                // Convert view deltas to doc deltas and apply
                let dxDoc = vx / z
                let dyDoc = vy / z
                sink?.setUniform("translation.x", float: Float(txCur + dxDoc))
                sink?.setUniform("translation.y", float: Float(tyCur + dyDoc))
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type": "ui.pan.debug",
                    "dx.view": vx,
                    "dy.view": vy,
                    "dx.doc": dxDoc,
                    "dy.doc": dyDoc
                ])
            }
        case "canvas.reset":
            // Reset canvas transform to canonical defaults
            NotificationCenter.default.post(
                name: Notification.Name("MetalCanvasRendererCommand"),
                object: nil,
                userInfo: [
                    "op": "set",
                    "zoom": Double(Canvas2D.defaultZoom),
                    "tx": Double(Canvas2D.defaultTranslation.x),
                    "ty": Double(Canvas2D.defaultTranslation.y)
                ]
            )
            // Emit monitor activity like App sink does so tests and overlays wake
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "ui.zoom", "zoom": Double(Canvas2D.defaultZoom)])
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "ui.pan", "x": 0.0, "y": 0.0])
        // Removed: context menu and add-instrument vendor JSON are not supported in baseline
        case "marquee.begin", "marquee.update", "marquee.end", "marquee.cancel":
            // Marquee selection removed: ignore gracefully for backward compatibility
            break
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
        if let value = item["value"] as? Double {
            sink?.setUniform(name, float: Float(value))
        }
    }

    func publishStateCI(requestId: UInt32? = nil) {
        // Compose property snapshot as JSON
        var snapshot: [String: Any] = [
            "identity": [
                "manufacturer": desc.manufacturer,
                "product": desc.product,
                "instanceId": desc.instanceId
            ],
            "pe": ["version": 1, "supports": ["get", "set"]]
        ]
        if let props = stateProvider?() { snapshot["properties"] = props }
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
            let w1 = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
            let w2 = (UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7])
            words.append(w1); words.append(w2)
        }
        return words
    }

    private func sendSysEx7UMP(bytes: [UInt8], group: UInt8 = 0) {
        let words = buildSysEx7Words(bytes: bytes, group: group)
        guard let session else { return }
        session.send(words: words)
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

    // MARK: - Convenience: Channel Voice UMP senders (Note/CC/PB)
    // These helpers let hosts drive external instruments (e.g., Csound) directly from view logic.
    // Values use MIDI 2.0 encodings: 16-bit velocity for notes; 32-bit values for CC/PB.
    public func sendNoteOn(note: UInt8, velocity7: UInt8 = 100, channel: UInt8 = 0, group: UInt8 = 0) {
        let mt: UInt32 = 0x4
        let statusHi: UInt32 = 0x9 // Note On
        let v16: UInt16 = UInt16(UInt32(velocity7) * 65535 / 127)
        let w1 = (mt << 28)
            | (UInt32(group & 0xF) << 24)
            | (statusHi << 20)
            | (UInt32(channel & 0xF) << 16)
            | (UInt32(note) << 8)
        let w2 = UInt32(v16) << 16 // attrType=0, attrData=0
        session?.send(words: [w1, w2])
    }

    public func sendNoteOff(note: UInt8, velocity7: UInt8 = 0, channel: UInt8 = 0, group: UInt8 = 0) {
        let mt: UInt32 = 0x4
        let statusHi: UInt32 = 0x8 // Note Off
        let v16: UInt16 = UInt16(UInt32(velocity7) * 65535 / 127)
        let w1 = (mt << 28)
            | (UInt32(group & 0xF) << 24)
            | (statusHi << 20)
            | (UInt32(channel & 0xF) << 16)
            | (UInt32(note) << 8)
        let w2 = UInt32(v16) << 16
        session?.send(words: [w1, w2])
    }

    public func sendCC(controller: UInt8, value7: UInt8, channel: UInt8 = 0, group: UInt8 = 0) {
        let mt: UInt32 = 0x4
        let statusHi: UInt32 = 0xB // CC
        let value32: UInt32 = UInt32(UInt64(value7) * 0xFFFF_FFFF / 127)
        let w1 = (mt << 28)
            | (UInt32(group & 0xF) << 24)
            | (statusHi << 20)
            | (UInt32(channel & 0xF) << 16)
            | (UInt32(controller) << 8)
        let w2 = value32
        session?.send(words: [w1, w2])
    }

    public func sendPitchBend(value14: UInt16, channel: UInt8 = 0, group: UInt8 = 0) {
        let mt: UInt32 = 0x4
        let statusHi: UInt32 = 0xE // PB
        let value32: UInt32 = UInt32(UInt64(value14) * 0xFFFF_FFFF / 0x3FFF)
        let w1 = (mt << 28)
            | (UInt32(group & 0xF) << 24)
            | (statusHi << 20)
            | (UInt32(channel & 0xF) << 16)
        let w2 = value32
        session?.send(words: [w1, w2])
    }

    private func handleEnableFailure(token: UUID, message: String, error: Error?) {
        guard enableToken == token else { return }
        enableToken = nil
        notifyTransportFailure(message: message, error: error)
    }

    private func notifyTransportFailure(message: String, error: Error?) {
        NotificationCenter.default.post(name: .MetalInstrumentTransportError, object: nil, userInfo: [
            "displayName": desc.displayName,
            "message": message,
            "error": error?.localizedDescription ?? ""
        ])
    }

    public static func setTransportOverride(_ transport: (any MetalInstrumentTransport)?) {
        transportHolder.set(transport)
    }

    public static func defaultTransport() -> any MetalInstrumentTransport {
        transportHolder.get()
    }

    private static func makeSystemDefaultTransport() -> any MetalInstrumentTransport {
        // Prefer loopback in robot-only mode to avoid CoreMIDI flakiness in tests
        if ProcessInfo.processInfo.environment["ROBOT_ONLY"] == "1" || ProcessInfo.processInfo.environment["FK_ROBOT_ONLY"] == "1" {
            return LoopbackMetalInstrumentTransport.shared
        }
        #if canImport(CoreMIDI)
        return CoreMIDIMetalInstrumentTransport.shared
        #else
        return NoopMetalInstrumentTransport()
        #endif
    }
}

private final class TransportHolder: @unchecked Sendable {
    private let lock = NSLock()
    private let defaultTransport: any MetalInstrumentTransport
    private var current: any MetalInstrumentTransport

    init(defaultTransport: any MetalInstrumentTransport) {
        self.defaultTransport = defaultTransport
        self.current = defaultTransport
    }

    func get() -> any MetalInstrumentTransport {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ transport: (any MetalInstrumentTransport)?) {
        lock.lock()
        if let transport {
            current = transport
        } else {
            current = defaultTransport
        }
        lock.unlock()
    }
}

public extension Notification.Name {
    static let MetalInstrumentTransportError = Notification.Name("MetalInstrumentTransportError")
    static let MetalCanvasMarqueeCommand = Notification.Name("MetalCanvasMarqueeCommand") // legacy (ignored)
}
