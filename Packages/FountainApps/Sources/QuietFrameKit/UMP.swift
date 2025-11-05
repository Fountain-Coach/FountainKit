import Foundation

public enum QFUMP {
    // Pack SysEx7 bytes into UMP words (MIDI 2.0) with group 0
    public static func packSysEx7(_ bytes: [UInt8], group: UInt8 = 0) -> [UInt32] {
        var words: [UInt32] = []
        var idx = 0
        while idx < bytes.count {
            let remain = bytes.count - idx
            let n = min(6, remain)
            let status: UInt8
            if idx == 0 && n == remain { status = 0x0 }
            else if idx == 0 { status = 0x2 }
            else if n == remain { status = 0x3 }
            else { status = 0x1 }
            var b = Array(bytes[idx..<(idx+n)])
            while b.count < 6 { b.append(0) }
            let w1 = (UInt32(0x3) << 28) | (UInt32(group & 0xF) << 24) | (UInt32(status & 0xF) << 20) | (UInt32(n & 0xF) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(w1); words.append(w2)
            idx += n
        }
        return words
    }

    // Unpack SysEx7 UMP words into bytes; returns empty on non-SysEx7
    public static func unpackSysEx7(words: [UInt32]) -> [UInt8] {
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
        return bytes
    }
}

