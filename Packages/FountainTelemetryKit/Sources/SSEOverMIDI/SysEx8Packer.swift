import Foundation
import MIDI2

public final class SysEx8Packer {
    private static let maxChunk = 14

    public init() {}

    public func pack(streamID: UInt8, blob: Data, group: UInt8) -> [Ump128] {
        var message = [streamID]
        message += [UInt8](blob)
        var packets: [Ump128] = []
        var index = 0
        while index < message.count {
            let remaining = message.count - index
            let size = min(Self.maxChunk, remaining)
            let chunk = Array(message[index..<index + size])
            let status: UInt8
            if message.count <= Self.maxChunk {
                status = 0x0
            } else if index == 0 {
                status = 0x1
            } else if remaining <= Self.maxChunk {
                status = 0x3
            } else {
                status = 0x2
            }
            var bytes = [UInt8](repeating: 0, count: 16)
            bytes[0] = 0x50 | (group & 0x0F)
            bytes[1] = (status << 4) | UInt8(size)
            for i in 0..<size { bytes[2 + i] = chunk[i] }
            let word0 = UInt32(bytes[0]) << 24 |
                        UInt32(bytes[1]) << 16 |
                        UInt32(bytes[2]) << 8  |
                        UInt32(bytes[3])
            let word1 = UInt32(bytes[4]) << 24 |
                        UInt32(bytes[5]) << 16 |
                        UInt32(bytes[6]) << 8  |
                        UInt32(bytes[7])
            let word2 = UInt32(bytes[8]) << 24 |
                        UInt32(bytes[9]) << 16 |
                        UInt32(bytes[10]) << 8 |
                        UInt32(bytes[11])
            let word3 = UInt32(bytes[12]) << 24 |
                        UInt32(bytes[13]) << 16 |
                        UInt32(bytes[14]) << 8 |
                        UInt32(bytes[15])
            packets.append(Ump128(word0: word0, word1: word1, word2: word2, word3: word3)!)
            index += size
        }
        return packets
    }

    public func unpack(umps: [Ump128]) -> [(streamID: UInt8, blob: Data)] {
        var results: [(UInt8, Data)] = []
        var buffer: [UInt8] = []
        var currentStream: UInt8? = nil
        for pkt in umps {
            let bytes = bytes(from: pkt)
            let status = bytes[1] >> 4
            let count = Int(bytes[1] & 0x0F)
            let data = Array(bytes[2..<(2 + count)])
            switch status {
            case 0x0:
                guard let sid = data.first else { continue }
                results.append((sid, Data(data.dropFirst())))
            case 0x1:
                currentStream = data.first
                buffer = Array(data.dropFirst())
            case 0x2:
                buffer.append(contentsOf: data)
            case 0x3:
                if let sid = currentStream {
                    buffer.append(contentsOf: data)
                    results.append((sid, Data(buffer)))
                    buffer.removeAll()
                    currentStream = nil
                }
            default:
                continue
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
