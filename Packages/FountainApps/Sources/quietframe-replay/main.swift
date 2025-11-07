import Foundation
import MIDI2Transports

@main
struct QuietFrameReplayMain {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var path: String = ".fountain/artifacts/quietframe/journal-events.ndjson"
        var dest: String? = nil
        var sleepUs: UInt64 = 5000 // 5 ms default pacing
        var i = 0
        while i < args.count {
            let tok = args[i]
            if tok == "--dest", i+1 < args.count { dest = args[i+1]; i += 2; continue }
            if tok == "--file", i+1 < args.count { path = args[i+1]; i += 2; continue }
            if tok == "--pacing-us", i+1 < args.count, let v = UInt64(args[i+1]) { sleepUs = v; i += 2; continue }
            if tok == "--help" || tok == "-h" {
                fputs("Usage: quietframe-replay [--file path] [--dest name] [--pacing-us 5000]\n", stderr)
                return
            }
            // First free arg as file
            if tok.first != "-" { path = tok; i += 1; continue }
            i += 1
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs("[replay] file not found: \(path)\n", stderr)
            return
        }

        // Open CoreMIDI transport (virtual endpoints + optional destination name)
        var transport: CoreMIDITransport?
        if #available(macOS 13.0, *) {
            let t = CoreMIDITransport(name: "QuietFrameReplay", destinationName: dest, enableVirtualEndpoints: true)
            try? t.open()
            transport = t
            let names = CoreMIDITransport.destinationNames().joined(separator: ", ")
            print("[replay] CoreMIDI opened. Destinations=\(names)")
        } else {
            print("[replay] CoreMIDI not available; running dry-run (no send)")
        }

        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        var count = 0
        while let line = fh.readLine() {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let arr = obj["ump"] as? [String] {
                let words: [UInt32] = arr.compactMap { s in UInt32(s.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                if !words.isEmpty {
                    if let t = transport { try? t.send(umpWords: words) }
                    count += 1
                    if sleepUs > 0 { usleep(useconds_t(sleepUs)) }
                }
            } else if let note = obj["note"] as? Int, let velocity = obj["velocity"] as? Int {
                // Fallback: synthesize CV2 words
                let words = packCV2Note(group: 0, channel: 0, note: UInt8(note), velocity7: UInt8(velocity), isOn: (obj["kind"] as? String) != "noteOff")
                if let t = transport { try? t.send(umpWords: words) }
                count += 1
                if sleepUs > 0 { usleep(useconds_t(sleepUs)) }
            }
        }
        print("[replay] sent \(count) UMP events from \(path)")
    }

    private static func packCV2Note(group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8, isOn: Bool) -> [UInt32] {
        let g = UInt32(group & 0x0F)
        let ch = UInt32(channel & 0x0F)
        let n = UInt32(note & 0x7F)
        let code: UInt32 = isOn ? 0x9 : 0x8
        let w0 = (UInt32(0x4) << 28) | (g << 24) | (code << 20) | (ch << 16) | (n << 8)
        let v16 = UInt16((UInt32(velocity7) * 65535) / 127)
        let w1 = UInt32(v16) << 16
        return [w0, w1]
    }
}

fileprivate extension FileHandle {
    func readLine() -> String? {
        var data = Data()
        while true {
            let chunk = try? self.read(upToCount: 1)
            if chunk == nil || chunk!.isEmpty { return data.isEmpty ? nil : String(decoding: data, as: UTF8.self) }
            if chunk![0] == 0x0A { return String(decoding: data, as: UTF8.self) }
            data.append(chunk!)
        }
    }
}

