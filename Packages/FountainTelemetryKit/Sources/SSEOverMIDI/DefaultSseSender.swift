import Foundation
import MIDI2
import MIDI2Core
import MIDI2Transports

public final class DefaultSseSender: SseOverMidiSender, @unchecked Sendable {
    private let rtp: RTPMidiSession
    private let flex: FlexPacker
    private let sysx: SysEx8Packer
    private let rel: Reliability
    private let metrics: Metrics?
    private var nextSeq: UInt64 = 0
    private let mtu: Int
    private var buffer: [[UInt32]] = []
    private var bufferBytes: Int = 0
    private var window: Int = .max
    private var pending: Set<UInt64> = []
    private let flexCapacity = 12 * 32

    public init(rtp: RTPMidiSession, flex: FlexPacker, sysx: SysEx8Packer, rel: Reliability, metrics: Metrics? = nil, mtu: Int = 1200) {
        self.rtp = rtp
        self.flex = flex
        self.sysx = sysx
        self.rel = rel
        self.metrics = metrics
        self.mtu = mtu
    }

    public func send(event: SseEnvelope) throws {
        prunePending()
        while pending.count >= window {
            flush()
            prunePending()
            if pending.count >= window {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        let seq = allocateSeq()
        let ts = Timing.jrNow()
        let env = SseEnvelope(
            v: event.v,
            ev: event.ev,
            id: event.id,
            ct: event.ct,
            seq: seq,
            frag: event.frag,
            ts: ts,
            data: event.data
        )

        let data = try JSONEncoder().encode(env)
        metrics?.addSend(bytes: data.count)
        let frames: [Ump128]
        if data.count > flexCapacity {
            frames = sysx.pack(streamID: 0x00, blob: data, group: 0x1)
        } else {
            frames = flex.pack(json: data, group: 0x1, statusBank: 0x01, status: 0x01)
        }
        rel.record(seq: env.seq, frames: frames)
        pending.insert(env.seq)

        for f in frames {
            let words = f.words
            let bytes = words.count * 4
            if bufferBytes + bytes + 12 > mtu {
                flush()
            }
            buffer.append(words)
            bufferBytes += bytes
        }
    }

    public func flush() {
        guard !buffer.isEmpty else { return }
        do {
            try rtp.send(umps: buffer)
        } catch {
            // Swallow send errors for now
        }
        buffer.removeAll()
        bufferBytes = 0
    }

    public func setWindow(_ n: Int) {
        window = n
    }

    public func close() {
        try? rtp.close()
    }

    private func allocateSeq() -> UInt64 {
        defer { nextSeq &+= 1 }
        return nextSeq
    }

    private func prunePending() {
        pending = pending.filter { $0 > rel.highestAcked }
    }

    public func listen(to receiver: DefaultSseReceiver) {
        receiver.onCtrl = { [weak self] env in
            guard let self = self else { return }
            guard let resend = self.rel.handleCtrl(env) else { return }
            for (_, frames) in resend.sorted(by: { $0.key < $1.key }) {
                do {
                    try self.rtp.send(umps: frames.map { $0.words })
                } catch {
                    // ignore send errors for retransmissions
                }
            }
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
