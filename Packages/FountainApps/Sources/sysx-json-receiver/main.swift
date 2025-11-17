import Foundation
import MIDI2Transports

@main
struct SysExJSONReceiver {
    static func main() {
        let loop = LoopbackTransport()
        loop.onReceiveUMP = { words in
            guard !words.isEmpty else { return }
            let mt = (words[0] >> 28) & 0xF
            guard mt == 0x3 else { return }
            let payload = decodeSysEx7UMP(words)
            guard !payload.isEmpty, let json = String(bytes: payload, encoding: .utf8) else { return }
            print(json)
        }
        try? loop.open()
        FileHandle.standardError.write(Data("[sysx-json-receiver] listening on loopback (SysEx7 JSON)\n".utf8))
        dispatchMain()
    }
}

private func decodeSysEx7UMP(_ words: [UInt32]) -> [UInt8] {
    var out: [UInt8] = []
    var i = 0
    while i + 1 < words.count {
        let w1 = words[i], w2 = words[i+1]
        if ((w1 >> 28) & 0xF) != 0x3 { break }
        let n = Int((w1 >> 16) & 0xF)
        let b0 = UInt8((w1 >> 8) & 0xFF)
        let b1 = UInt8(w1 & 0xFF)
        let b2 = UInt8((w2 >> 24) & 0xFF)
        let b3 = UInt8((w2 >> 16) & 0xFF)
        let b4 = UInt8((w2 >> 8) & 0xFF)
        let b5 = UInt8(w2 & 0xFF)
        let chunk = [b0,b1,b2,b3,b4,b5].prefix(n)
        out.append(contentsOf: chunk)
        i += 2
    }
    return out
}

