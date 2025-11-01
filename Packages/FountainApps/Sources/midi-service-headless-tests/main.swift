import Foundation

@main
struct MIDIServiceHeadlessTests {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let base = env["MIDI_SERVICE_URL"] ?? "http://127.0.0.1:7180"
        func url(_ path: String) -> URL { URL(string: base + path)! }

        // Helpers: minimal SysEx7 vendor JSON → UMP (2 words per packet)
        func buildVendorJSON(topic: String, data: [String: Any]) -> [UInt8] {
            let header: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4F, 0x4E, 0x00]
            let tail: [UInt8] = [0xF7]
            let body = (try? JSONSerialization.data(withJSONObject: ["topic": topic, "data": data])) ?? Data()
            var out = header
            out.append(contentsOf: body)
            out.append(contentsOf: tail)
            return out
        }
        func encodeSysEx7UMP(bytes: [UInt8], group: UInt8 = 0) -> [UInt32] {
            var words: [UInt32] = []
            let chunks: [[UInt8]] = stride(from: 0, to: bytes.count, by: 6).map { i in Array(bytes[i..<min(i+6, bytes.count)]) }
            for (idx, chunk) in chunks.enumerated() {
                let status: UInt8
                if chunks.count == 1 { status = 0x0 }
                else if idx == 0 { status = 0x1 }
                else if idx == chunks.count - 1 { status = 0x3 }
                else { status = 0x2 }
                var b = [UInt8](repeating: 0, count: 8)
                b[0] = (0x3 << 4) | (group & 0xF)
                b[1] = (status << 4) | UInt8(chunk.count & 0xF)
                for i in 0..<chunk.count { b[2+i] = chunk[i] }
                let w1 = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
                let w2 = (UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7])
                words.append(w1)
                words.append(w2)
            }
            return words
        }

        func postJSON(_ path: String, _ obj: Any) async throws {
            var req = URLRequest(url: url(path))
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: obj)
            _ = try await URLSession.shared.data(for: req)
        }
        func getJSON(_ path: String) async throws -> Any {
            let (data, _) = try await URLSession.shared.data(from: url(path))
            return try JSONSerialization.jsonObject(with: data)
        }

        do {
            // Flush recorder
            try await postJSON("/ump/flush", [:])
            // Step 1: editor text.set
            let words = encodeSysEx7UMP(bytes: buildVendorJSON(topic: "text.set", data: ["text": "Hello editor", "cursor": 12]))
            try await postJSON("/ump/send", ["target": ["displayName": "Fountain Editor"], "words": words])
            try? await Task.sleep(nanoseconds: 300_000_000)
            // Assert text.parsed appears in tail
            if let tail = try await getJSON("/ump/tail") as? [String: Any], let events = tail["events"] as? [[String: Any]] {
                let types: [String] = events.compactMap { ev in
                    if let v = ev["vendorJSON"] as? String, let data = v.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        return obj["type"] as? String
                    }
                    return nil
                }
                guard types.contains("text.parsed") else {
                    fputs("[tests] FAIL: text.parsed not found\n", stderr)
                    exit(1)
                }
            }

            // Step 2: corpus.baseline.add (direct) → expect corpus.baseline.added
            try await postJSON("/ump/flush", [:])
            let words2 = encodeSysEx7UMP(bytes: buildVendorJSON(topic: "corpus.baseline.add", data: ["text": "INT. ROOM – DAY\nJOHN\nHello.\n"]))
            try await postJSON("/ump/send", ["target": ["displayName": "Corpus Instrument"], "words": words2])
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let tail2 = try await getJSON("/ump/tail") as? [String: Any], let events = tail2["events"] as? [[String: Any]] {
                let types: [String] = events.compactMap { ev in
                    if let v = ev["vendorJSON"] as? String, let data = v.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        return obj["type"] as? String
                    }
                    return nil
                }
                guard types.contains("corpus.baseline.added") else {
                    fputs("[tests] FAIL: corpus.baseline.added not found\n", stderr)
                    exit(1)
                }
            }

            print("[tests] OK: editor text.parsed and submit→baseline.added")
        } catch {
            fputs("[tests] ERROR: \(error)\n", stderr)
            exit(2)
        }
    }
}
