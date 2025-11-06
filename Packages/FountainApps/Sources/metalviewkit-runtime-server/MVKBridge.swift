import Foundation
import MetalViewKit

/// MVKBridge offers a tiny shim for tests to forward runtime UMP words
/// to a running MetalViewKit instrument by display name.
///
/// In ROBOT_ONLY mode, the default transport is Loopback; otherwise CoreMIDI.
public enum MVKBridge {
    /// Sends UMP words to the first MVK instrument whose display name contains `displayNameSubstring`.
    /// Returns true when a matching instrument was found and accepted the words.
    @discardableResult
    public static func sendUMP(words: [UInt32], toDisplayNameContaining displayNameSubstring: String) -> Bool {
        LoopbackMetalInstrumentTransport.shared.send(words: words, toDisplayName: displayNameSubstring)
    }

    /// Sends a batch of UMP words arrays to a target resolved from parameters/env.
    /// Priority: instanceId > displayName substring > MVK_BRIDGE_TARGET env > "Canvas".
    @discardableResult
    public static func sendBatch(_ batch: [[UInt32]],
                                 targetDisplayNameSubstring: String? = nil,
                                 targetInstanceId: String? = nil) -> Int {
        var delivered = 0
        if let iid = targetInstanceId, !iid.isEmpty {
            for words in batch { if LoopbackMetalInstrumentTransport.shared.send(words: words, toInstanceId: iid) { delivered += 1 } }
            return delivered
        }
        let fallback = ProcessInfo.processInfo.environment["MVK_BRIDGE_TARGET"] ?? "Canvas"
        let target = (targetDisplayNameSubstring?.isEmpty == false) ? targetDisplayNameSubstring! : fallback
        for words in batch { if LoopbackMetalInstrumentTransport.shared.send(words: words, toDisplayName: target) { delivered += 1 } }
        return delivered
    }

    // Build SysEx7 UMP words from a raw bytes payload (6 data bytes per packet)
    private static func buildSysEx7Words(bytes: [UInt8], group: UInt8 = 0) -> [UInt32] {
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

    @discardableResult
    public static func sendVendorJSON(topic: String,
                                      data: [String: Any] = [:],
                                      targetDisplayNameSubstring: String? = nil,
                                      targetInstanceId: String? = nil,
                                      group: UInt8 = 0) -> Bool {
        var payload: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00]
        var body: [String: Any] = ["topic": topic]
        if !data.isEmpty { body["data"] = data }
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        payload.append(contentsOf: json)
        payload.append(0xF7)
        let words = buildSysEx7Words(bytes: payload, group: group)
        return sendBatch([words], targetDisplayNameSubstring: targetDisplayNameSubstring, targetInstanceId: targetInstanceId) > 0
    }
}
