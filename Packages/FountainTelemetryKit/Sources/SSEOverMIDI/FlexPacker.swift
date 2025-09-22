import Foundation
import MIDI2

public enum FlexFormat: UInt8 {
    case complete = 0x0
    case start = 0x1
    case `continue` = 0x2
    case end = 0x3
}

public struct FlexChunk {
    public let group: UInt8
    public let format: FlexFormat
    public let statusBank: UInt8
    public let status: UInt8
    public let payload: [UInt8]

    public init(group: UInt8, format: FlexFormat, statusBank: UInt8, status: UInt8, payload: [UInt8]) {
        self.group = group
        self.format = format
        self.statusBank = statusBank
        self.status = status
        self.payload = payload
    }
}

public final class FlexPacker {
    private static let maxChunk = 12

    public init() {}

    public func pack(json: Data, group: UInt8, statusBank: UInt8, status: UInt8) -> [Ump128] {
        let bytes = [UInt8](json)
        var packets: [Ump128] = []
        var index = 0
        let total = Int(ceil(Double(bytes.count) / Double(Self.maxChunk)))
        while index < bytes.count {
            let remaining = bytes.count - index
            let size = min(Self.maxChunk, remaining)
            let chunk = Array(bytes[index..<index + size])
            let format: FlexFormat
            if total == 1 {
                format = .complete
            } else if index == 0 {
                format = .start
            } else if remaining <= Self.maxChunk {
                format = .end
            } else {
                format = .continue
            }
            let header = UmpHeader128(
                messageType: 0xD,
                group: Uint4(group & 0x0F)!,
                status: (format.rawValue << 4) | (statusBank & 0x0F),
                byte3: status,
                byte4: UInt8(size)
            )!
            var payload = chunk
            if payload.count < Self.maxChunk {
                payload += Array(repeating: 0, count: Self.maxChunk - payload.count)
            }
            let word1 = UInt32(payload[0]) << 24 |
                        UInt32(payload[1]) << 16 |
                        UInt32(payload[2]) << 8 |
                        UInt32(payload[3])
            let word2 = UInt32(payload[4]) << 24 |
                        UInt32(payload[5]) << 16 |
                        UInt32(payload[6]) << 8 |
                        UInt32(payload[7])
            let word3 = UInt32(payload[8]) << 24 |
                        UInt32(payload[9]) << 16 |
                        UInt32(payload[10]) << 8 |
                        UInt32(payload[11])
            packets.append(Ump128(header: header, word1: word1, word2: word2, word3: word3))
            index += size
        }
        return packets
    }

    public func unpack(umps: [Ump128]) -> [Data] {
        var results: [Data] = []
        var buffer: [UInt8] = []
        var collecting = false
        for pkt in umps {
            let bytes = bytes(from: pkt)
            let formatRaw = (bytes[1] >> 4) & 0x0F
            guard let format = FlexFormat(rawValue: formatRaw) else { continue }
            let count = Int(bytes[3])
            let payload = Array(bytes[4..<16]).prefix(count)
            switch format {
            case .complete:
                results.append(Data(payload))
            case .start:
                buffer = Array(payload)
                collecting = true
            case .continue:
                if collecting { buffer.append(contentsOf: payload) }
            case .end:
                if collecting {
                    buffer.append(contentsOf: payload)
                    results.append(Data(buffer))
                    buffer.removeAll()
                    collecting = false
                }
            }
        }
        return results
    }

    private func bytes(from packet: Ump128) -> [UInt8] {
        [
            UInt8((packet.word0 >> 24) & 0xFF),
            UInt8((packet.word0 >> 16) & 0xFF),
            UInt8((packet.word0 >> 8) & 0xFF),
            UInt8(packet.word0 & 0xFF),
            UInt8((packet.word1 >> 24) & 0xFF),
            UInt8((packet.word1 >> 16) & 0xFF),
            UInt8((packet.word1 >> 8) & 0xFF),
            UInt8(packet.word1 & 0xFF),
            UInt8((packet.word2 >> 24) & 0xFF),
            UInt8((packet.word2 >> 16) & 0xFF),
            UInt8((packet.word2 >> 8) & 0xFF),
            UInt8(packet.word2 & 0xFF),
            UInt8((packet.word3 >> 24) & 0xFF),
            UInt8((packet.word3 >> 16) & 0xFF),
            UInt8((packet.word3 >> 8) & 0xFF),
            UInt8(packet.word3 & 0xFF)
        ]
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
