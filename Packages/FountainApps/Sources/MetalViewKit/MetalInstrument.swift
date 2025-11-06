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
                    // Observe recorder-state changes and publish PE notify so companions reflect rec.state
                    NotificationCenter.default.addObserver(forName: Notification.Name("QuietFrameRecordStateChanged"), object: nil, queue: .main) { [weak self] _ in
                        self?.publishStateCI()
                    }
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

    private func handleEnableFailure(token: UUID, message: String, error: Error?) {
        // Minimal diagnostic; real implementation may publish state or notify
        #if DEBUG
        print("[MetalInstrument] enable failed: \(message) \(error.map { String(describing: $0) } ?? "")")
        #endif
        if enableToken == token { enableToken = nil }
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
                let v14 = UInt16(Double(v32) / 4294967295.0 * 16383.0)
                sink?.pitchBend(value14: v14, channel: ch, group: group)
            }
        case 0x3: // SysEx7
            let bytes = decodeSysEx7(words: words)
            handleSysEx7(bytes)
        default:
            break
        }
    }

    // MARK: - Vendor JSON via SysEx7
    private func decodeSysEx7(words: [UInt32]) -> [UInt8] {
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: words.count, by: 2) {
            let w1 = words[i]
            let w2 = (i + 1 < words.count) ? words[i + 1] : 0
            let n = Int((w1 >> 16) & 0xF)
            let b2 = UInt8((w1 >> 8) & 0xFF)
            let b3 = UInt8(w1 & 0xFF)
            let b4 = UInt8((w2 >> 24) & 0xFF)
            let b5 = UInt8((w2 >> 16) & 0xFF)
            let b6 = UInt8((w2 >> 8) & 0xFF)
            let b7 = UInt8(w2 & 0xFF)
            let chunk: [UInt8] = [b2, b3, b4, b5, b6, b7].prefix(n).map { $0 }
            bytes.append(contentsOf: chunk)
        }
        return bytes
    }

    private func handleSysEx7(_ bytes: [UInt8]) {
        guard bytes.count >= 7 else { return }
        guard bytes[0] == 0xF0 && bytes[1] == 0x7D && bytes[2] == 0x4A && bytes[3] == 0x53 && bytes[4] == 0x4E else { return }
        let typ = bytes[5]
        guard typ == 0x00 else { return } // Vendor JSON event
        let payload = Array(bytes.dropFirst(6).dropLast(bytes.last == 0xF7 ? 1 : 0))
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] else { return }
        let topic = json["topic"] as? String ?? "event"
        sink?.vendorEvent(topic: topic, data: json["data"]) // optional
    }

    // MARK: - State publish and vendor helpers
    private func publishStateCI() {
        guard let state = stateProvider?(), !state.isEmpty else { return }
        _ = sendVendorJSONEvent(topic: "state", dict: state)
    }

    @discardableResult
    public func sendVendorJSONEvent(topic: String, dict: [String: Any]) -> Bool {
        var payload: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00]
        var body: [String: Any] = ["topic": topic]
        if !dict.isEmpty { body["data"] = dict }
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        payload.append(contentsOf: json)
        payload.append(0xF7)
        let words = MetalInstrument.buildSysEx7Words(bytes: payload, group: desc.midiGroup)
        session?.send(words: words)
        return true
    }

    private static func buildSysEx7Words(bytes: [UInt8], group: UInt8) -> [UInt32] {
        let chunks: [[UInt8]] = stride(from: 0, to: bytes.count, by: 6).map { Array(bytes[$0..<min($0+6, bytes.count)]) }
        var words: [UInt32] = []
        for (idx, chunk) in chunks.enumerated() {
            let isSingle = chunks.count == 1
            let isFirst = idx == 0
            let isLast = idx == chunks.count - 1
            let status: UInt8 = isSingle ? 0x0 : (isFirst ? 0x1 : (isLast ? 0x3 : 0x2))
            let num = UInt8(chunk.count)
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
}

// MARK: - Transport holder and defaults
public protocol MetalSceneRenderer: AnyObject {
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8)
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8)
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8)
    func vendorEvent(topic: String, data: Any?)
}

final class TransportHolder: @unchecked Sendable {
    private var current: (any MetalInstrumentTransport)?
    private let fallback: any MetalInstrumentTransport
    private let lock = NSLock()
    init(defaultTransport: any MetalInstrumentTransport) { self.fallback = defaultTransport }
    func get() -> any MetalInstrumentTransport { lock.lock(); defer { lock.unlock() }; return current ?? fallback }
    func set(_ t: (any MetalInstrumentTransport)?) { lock.lock(); current = t; lock.unlock() }
}

extension MetalInstrument {
    static func makeSystemDefaultTransport() -> any MetalInstrumentTransport {
        #if canImport(MIDI2Transports)
        return MIDI2SystemInstrumentTransport()
        #else
        return LoopbackMetalInstrumentTransport.shared
        #endif
    }
    public static func setDefaultTransport(_ transport: (any MetalInstrumentTransport)?) {
        Self.transportHolder.set(transport)
    }
    public static func defaultTransport() -> any MetalInstrumentTransport {
        Self.transportHolder.get()
    }

    // Backward-compatible alias for legacy call sites
    public static func setTransportOverride(_ transport: (any MetalInstrumentTransport)?) {
        setDefaultTransport(transport)
    }

    // Convenience send helpers (Channel Voice 2.0)
    public func sendCC(controller: UInt8, value7: UInt8, channel: UInt8 = 0) {
        let group = desc.midiGroup
        let w0 = (UInt32(0x4) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(0xB) << 20) | (UInt32(channel & 0xF) << 16) | (UInt32(controller) << 8)
        // Scale 7-bit value (0..127) into full 32-bit domain (0..0xFFFF_FFFF) using 64-bit math to avoid overflow
        let v32 = UInt32((UInt64(value7) * UInt64(0xFFFF_FFFF)) / 127)
        session?.send(words: [w0, v32])
    }

    public func sendNoteOn(note: UInt8, velocity7: UInt8, channel: UInt8 = 0) {
        let group = desc.midiGroup
        let w0 = (UInt32(0x4) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(0x9) << 20) | (UInt32(channel & 0xF) << 16) | (UInt32(note) << 8)
        let v16 = UInt16(velocity7) * 65535 / 127
        let w1 = UInt32(v16) << 16
        session?.send(words: [w0, w1])
    }

    public func sendNoteOff(note: UInt8, velocity7: UInt8, channel: UInt8 = 0) {
        let group = desc.midiGroup
        let w0 = (UInt32(0x4) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(0x8) << 20) | (UInt32(channel & 0xF) << 16) | (UInt32(note) << 8)
        let v16 = UInt16(velocity7) * 65535 / 127
        let w1 = UInt32(v16) << 16
        session?.send(words: [w0, w1])
    }
}
