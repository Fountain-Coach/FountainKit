import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MIDI2Transports

@main
struct PlannerPEBridge {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let baseURL = URL(string: env["PLANNER_BASE_URL"] ?? "http://127.0.0.1:8020")!
        let requestPath = env["PLANNER_PLAN_PATH"] ?? "/planner/plan"
        let out = FileHandle.standardError
        out.write(Data("[planner-pe-bridge] starting (loopback) base=\(baseURL.absoluteString) path=\(requestPath)\n".utf8))

        let loop = LoopbackTransport()
        loop.onReceiveUMP = { words in
            // Expect SysEx7 UMP frames with a UTF-8 JSON body representing a PE SET
            if words.isEmpty { return }
            let mt = (words[0] >> 28) & 0xF
            guard mt == 0x3 else { return }
            let payload = decodeSysEx7UMP(words)
            guard !payload.isEmpty else { return }
            if let json = String(bytes: payload, encoding: .utf8) {
                Task {
                    await handle(json: json, baseURL: baseURL, path: requestPath, transport: loop)
                }
            }
        }
        do { try loop.open() } catch {
            out.write(Data("[planner-pe-bridge] loopback open failed: \(error)\n".utf8))
        }
        dispatchMain()
    }

    private static func handle(json: String, baseURL: URL, path: String, transport: LoopbackTransport) async {
        let out = FileHandle.standardError
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let prop = obj["propertyId"] as? String, prop == "planner.plan.request" else { return }
        let body = (obj["body"] as? [String: Any]) ?? [:]
        // POST to planner
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            let resultEnvelope: [String: Any] = [
                "propertyId": "planner.plan.result",
                "status": http.statusCode,
                "body": (try? JSONSerialization.jsonObject(with: data)) ?? [:]
            ]
            if let outData = try? JSONSerialization.data(withJSONObject: resultEnvelope),
               let bytes = String(data: outData, encoding: .utf8)?.utf8 {
                let umps = encodeSysEx7UMP(Array(bytes))
                for u in umps { try? transport.send(umpWords: u) }
            }
        } catch {
            out.write(Data("[planner-pe-bridge] HTTP error: \(error)\n".utf8))
        }
    }
}

// Minimal helpers (local copy) — UMP SysEx7 encode/decode (no 0xF0/0xF7 markers)
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
