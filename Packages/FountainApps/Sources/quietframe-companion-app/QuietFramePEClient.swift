import Foundation
import MIDI2
import MIDI2CI
import MetalViewKit
import QuietFrameKit

@MainActor final class QuietFramePEClient: ObservableObject {
    @Published var connectedName: String? = nil
    @Published var lastSnapshotJSON: String = ""
    @Published var recState: String = "idle"
    @Published var lastSavedURL: String? = nil
    @Published var lastSavedDuration: Double? = nil

    private let group: UInt8 = 0
    private var requestId: UInt32 = 1
    private var session: (any MetalInstrumentTransportSession)? = nil
    private var sidecar: QuietFrameSidecarClient? = nil
    private var useSidecar: Bool = true

    func connect(displayNameContains name: String = "QuietFrame#qf-1") {
        if useSidecar {
            let cfg = QuietFrameSidecarClient.Config(targetDisplayName: name)
            let client = QuietFrameSidecarClient(config: cfg)
            self.sidecar = client
            self.connectedName = "Sidecar: \(cfg.baseURL.absoluteString)"
            Task { [weak self] in
                await client.startPolling(pollIntervalMs: 100)
                await client.setOnUMPSink { words in
                    self?.handleIncoming(words)
                }
            }
        } else {
            let transport = MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(5868))
            let iid = UUID().uuidString
            let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "QuietFrame-Companion", instanceId: iid, displayName: "QuietFrameCompanion#\(iid)")
            do {
                self.session = try transport.makeSession(descriptor: desc) { [weak self] words in
                    self?.handleIncoming(words)
                }
                self.connectedName = name
                print("[quietframe-companion] MVK client instrument ready: displayName=\(desc.displayName) instanceId=\(desc.instanceId)")
            } catch {
                self.connectedName = "Transport error"
            }
        }
    }

    func get() {
        let pe = MidiCiPropertyExchangeBody(command: .get, requestId: requestId, encoding: .json, header: [:], data: [])
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        if useSidecar {
            Task { await sidecar?.injectSysEx7(bytes: env.sysEx7Payload()) }
        } else {
            sendSysEx7(bytes: env.sysEx7Payload())
        }
        requestId &+= 1
    }

    func set(_ pairs: [(String, Double)]) {
        let props = pairs.map { ["name": $0.0, "value": $0.1] }
        let obj: [String: Any] = ["properties": props]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let pe = MidiCiPropertyExchangeBody(command: .set, requestId: requestId, encoding: .json, header: [:], data: Array(data))
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        if useSidecar {
            Task { await sidecar?.injectSysEx7(bytes: env.sysEx7Payload()) }
        } else {
            sendSysEx7(bytes: env.sysEx7Payload())
        }
        requestId &+= 1
    }

    func sendVendor(topic: String, data: [String: Any] = [:]) {
        if useSidecar {
            Task { await sidecar?.sendVendor(topic: topic, data: data) }
        } else {
            var payload: [String: Any] = ["topic": topic]
            if !data.isEmpty { payload["data"] = data }
            guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
            var bytes: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00]
            bytes.append(contentsOf: Array(json))
            bytes.append(0xF7)
            sendSysEx7(bytes: bytes)
        }
    }

    // Emit event JSON on the main actor to avoid cross-actor crashes
    var eventSink: ((String) -> Void)? = nil

    private func sendSysEx7(bytes: [UInt8]) {
        var words: [UInt32] = []
        var idx = 0
        let total = bytes.count
        while idx < total {
            let remain = total - idx
            let n = min(remain, 6)
            let status: UInt8
            if idx == 0 && n == remain { status = 0x0 } else if idx == 0 { status = 0x2 } else if n == remain { status = 0x3 } else { status = 0x1 }
            var b: [UInt8] = Array(bytes[idx..<(idx+n)])
            while b.count < 6 { b.append(0) }
            let w1 = (UInt32(0x3) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(status & 0xF) << 20) | (UInt32(n & 0xF) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(w1); words.append(w2)
            idx += n
        }
        session?.send(words: words)
        if let sink = eventSink {
            let payload = words.map { String(format: "0x%08X", $0) }
            if let data = try? JSONSerialization.data(withJSONObject: ["dir":"out","ump": payload], options: []), let s = String(data: data, encoding: .utf8) {
                Task { @MainActor in sink(s) }
            }
        }
    }
}

// MARK: - Inbound handling via RTP transport
extension QuietFramePEClient {
    nonisolated private func handleIncoming(_ words: [UInt32]) {
        // SysEx7 only for now (UMP SysEx7 decode)
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
        // Vendor JSON inbound (rec.saved)
        if bytes.count >= 8, bytes[0] == 0xF0, bytes[1] == 0x7D, bytes[2] == 0x4A, bytes[3] == 0x53, bytes[4] == 0x4F, bytes[5] == 0x4E, bytes[6] == 0x00 {
            let body = Data(bytes[7..<(bytes.count-1)])
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let topic = obj["topic"] as? String {
                if topic == "rec.saved", let data = obj["data"] as? [String: Any] {
                    let url = data["url"] as? String
                    let dur = data["durationSec"] as? Double
                    Task { @MainActor in
                        self.lastSavedURL = url
                        self.lastSavedDuration = dur
                    }
                }
            }
        } else if let env = try? MidiCiEnvelope(sysEx7Payload: bytes) {
            if case .propertyExchange(let pe) = env.body, (pe.command == .getReply || pe.command == .notify) {
                if let obj = try? JSONSerialization.jsonObject(with: Data(pe.data)) as? [String: Any] {
                    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]), let s = String(data: data, encoding: .utf8) {
                        Task { @MainActor in self.lastSnapshotJSON = s }
                    }
                    if let props = obj["properties"] as? [String: Any], let rs = props["rec.state"] as? String {
                        Task { @MainActor in self.recState = rs }
                    }
                }
            }
        }
        // Emit event JSON for UI
        let payload = words.map { String(format: "0x%08X", $0) }
        if let data = try? JSONSerialization.data(withJSONObject: ["dir":"in","ump": payload], options: []), let s = String(data: data, encoding: .utf8) {
            Task { @MainActor in self.eventSink?(s) }
        }
    }
}

// MARK: - Sidecar helpers
extension QuietFrameSidecarClient {
    public func setOnUMPSink(_ sink: @escaping @Sendable ([UInt32]) -> Void) {
        self.onUMP = sink
    }
}
