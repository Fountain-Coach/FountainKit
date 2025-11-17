import Foundation
import MIDI2Transports

@main
struct SysExJSONSender {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let inputPath = CommandLine.arguments.dropFirst().first ?? env["JSON_FILE"]
        let jsonText: String
        if let path = inputPath, !path.isEmpty {
            jsonText = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "{}"
        } else if let inline = env["JSON_TEXT"], !inline.isEmpty {
            jsonText = inline
        } else {
            if let data = try? FileHandle.standardInput.readToEnd(), let s = String(data: data, encoding: .utf8) {
                jsonText = s
            } else { jsonText = "{}" }
        }
        let loop = LoopbackTransport()
        try? loop.open()
        let bytes = Array(jsonText.utf8)
        for u in encodeSysEx7UMP(bytes) { try? loop.send(umpWords: u) }
        fputs("sent JSON as SysEx7 over loopback (\(bytes.count) bytes)\n", stderr)
    }
}

private func encodeSysEx7UMP(_ bytes: [UInt8]) -> [[UInt32]] {
    if bytes.isEmpty { return [] }
    var umps: [[UInt32]] = []
    var idx = 0
    var first = true
    while idx < bytes.count {
        let remain = bytes.count - idx
        let n = min(6, remain)
        let status: UInt8
        if first && n == remain { status = 0x0 }
        else if first { status = 0x1 }
        else if n == remain { status = 0x3 }
        else { status = 0x2 }
        var chunk = Array(bytes[idx..<(idx+n)])
        while chunk.count < 6 { chunk.append(0) }
        let w1 = (UInt32(0x3) << 28) | (0 << 24) | (UInt32(status) << 20) | (UInt32(n) << 16) | (UInt32(chunk[0]) << 8) | UInt32(chunk[1])
        let w2 = (UInt32(chunk[2]) << 24) | (UInt32(chunk[3]) << 16) | (UInt32(chunk[4]) << 8) | UInt32(chunk[5])
        umps.append([w1, w2])
        idx += n
        first = false
    }
    return umps
}

