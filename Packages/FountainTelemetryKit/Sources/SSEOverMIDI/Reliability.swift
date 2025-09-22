import Foundation
import MIDI2
import MIDI2Core

public final class Reliability {
    private(set) var highestAcked: UInt64 = 0
    private var buffer: [UInt64: [Ump128]] = [:]
    private let maxBuffer: Int = 512
    private let metrics: Metrics?

    public init(metrics: Metrics? = nil) {
        self.metrics = metrics
    }

    /// Store frames for potential retransmission.
    /// Keeps the buffer bounded by removing the lowest sequence when exceeding `maxBuffer` entries.
    public func record(seq: UInt64, frames: [Ump128]) {
        buffer[seq] = frames
        if buffer.count > maxBuffer, let oldest = buffer.keys.sorted().first {
            buffer.removeValue(forKey: oldest)
        }
    }

    /// Build an ACK control envelope acknowledging `h`.
    public func buildAck(h: UInt64) -> SseEnvelope {
        metrics?.incAcksSent()
        return SseEnvelope(ev: "ctrl", seq: h, data: "{\"ack\":\(h)}")
    }

    public func buildNack(_ seqs: [UInt64]) -> SseEnvelope {
        metrics?.incNacksSent()
        let list = seqs.map(String.init).joined(separator: ",")
        return SseEnvelope(ev: "ctrl", seq: highestAcked, data: "{\"nack\":[\(list)]}")
    }

    /// Handle a received control envelope.
    /// Updates internal ACK state and returns frames to retransmit for any NACKed sequences.
    public func handleCtrl(_ env: SseEnvelope) -> [UInt64: [Ump128]]? {
        guard env.ev == "ctrl", let dataStr = env.data,
              let jsonData = dataStr.data(using: .utf8) else { return nil }
        struct Ctrl: Codable { let ack: UInt64?; let nack: [UInt64]? }
        guard let ctrl = try? JSONDecoder().decode(Ctrl.self, from: jsonData) else { return nil }

        if let ack = ctrl.ack {
            if ack > highestAcked { highestAcked = ack }
            buffer.keys.filter { $0 <= ack }.forEach { buffer.removeValue(forKey: $0) }
        }

        guard let nacks = ctrl.nack else { return nil }
        var resend: [UInt64: [Ump128]] = [:]
        var retransmitCount = 0
        for seq in nacks {
            if let frames = buffer[seq] {
                resend[seq] = frames
                retransmitCount += frames.count
            }
        }
        if retransmitCount > 0 {
            metrics?.incRetransmits(retransmitCount)
        }
        return resend.isEmpty ? nil : resend
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
