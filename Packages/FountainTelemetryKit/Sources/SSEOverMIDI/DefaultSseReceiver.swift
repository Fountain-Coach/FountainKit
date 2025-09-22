import Foundation
import MIDI2
import MIDI2Core
import MIDI2Transports

public final class DefaultSseReceiver: SseOverMidiReceiver {
    public var onEvent: ((SseEnvelope) -> Void)?
    public var onCtrl: ((SseEnvelope) -> Void)?
    private let rtp: RTPMidiSession
    private let flex: FlexPacker
    private let sysx: SysEx8Packer
    private let rel: Reliability
    private let metrics: Metrics?
    private var expectedSeq: UInt64 = 0
    private var pending: Set<UInt64> = []

    public init(rtp: RTPMidiSession, flex: FlexPacker, sysx: SysEx8Packer, rel: Reliability, metrics: Metrics? = nil) {
        self.rtp = rtp
        self.flex = flex
        self.sysx = sysx
        self.rel = rel
        self.metrics = metrics
        self.rtp.onReceiveUmps = { [weak self] packets in
            guard let self else { return }
            var flexUmps: [Ump128] = []
            var sysxUmps: [Ump128] = []
            for words in packets {
                guard let pkt = Ump128(words: words) else { continue }
                let mt = (pkt.word0 >> 28) & 0xF
                if mt == 0x5 {
                    sysxUmps.append(pkt)
                } else if mt == 0xD {
                    flexUmps.append(pkt)
                }
            }
            for (_, blob) in self.sysx.unpack(umps: sysxUmps) {
                self.handleBlob(blob)
            }
            for blob in self.flex.unpack(umps: flexUmps) {
                self.handleBlob(blob)
            }
        }
    }

    private func handleBlob(_ blob: Data) {
        guard let env = try? JSONDecoder().decode(SseEnvelope.self, from: blob) else { return }
        metrics?.addRecv(bytes: blob.count)
        rel.record(seq: env.seq, frames: [])
        if env.ev == "ctrl" {
            onCtrl?(env)
        } else {
            handleSeq(env.seq)
            if let ts = env.ts {
                let hostTs = Timing.hostTime(fromJR: ts)
                let translated = SseEnvelope(
                    v: env.v,
                    ev: env.ev,
                    id: env.id,
                    ct: env.ct,
                    seq: env.seq,
                    frag: env.frag,
                    ts: hostTs,
                    data: env.data
                )
                onEvent?(translated)
            } else {
                onEvent?(env)
            }
        }
    }

    private func handleSeq(_ seq: UInt64) {
        if seq == expectedSeq {
            expectedSeq &+= 1
            while pending.remove(expectedSeq) != nil {
                expectedSeq &+= 1
            }
            if expectedSeq > 0 {
                let ackVal = expectedSeq &- 1
                let ack = rel.buildAck(h: ackVal)
                sendCtrl(ack)
            }
        } else if seq > expectedSeq {
            metrics?.incSeqGapsDetected()
            let missing = Array(expectedSeq..<seq)
            let nack = rel.buildNack(missing)
            sendCtrl(nack)
            pending.insert(seq)
        } else {
            pending.remove(seq)
        }
    }

    private func sendCtrl(_ env: SseEnvelope) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        let frames = flex.pack(json: data, group: 0x1, statusBank: 0x1, status: 0x1)
        rel.record(seq: env.seq, frames: frames)
        let umps = frames.map { $0.words }
        try? rtp.send(umps: umps)
    }

    public func start() throws {
        try rtp.open()
    }

    public func stop() {
        try? rtp.close()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
