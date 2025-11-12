import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MIDI2Transports

@main
struct PersistPEBridge {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let baseURL = URL(string: env["PERSIST_BASE_URL"] ?? "http://127.0.0.1:8040")!
        let getPathTmpl = env["PERSIST_GET_PATH"] ?? "/persist/{collection}/{id}"
        let putPathTmpl = env["PERSIST_PUT_PATH"] ?? "/persist/{collection}/{id}"
        FileHandle.standardError.write(Data("[persist-pe-bridge] base=\(baseURL.absoluteString)\n".utf8))

        let loop = LoopbackTransport()
        loop.onReceiveUMP = { words in
            let mt = (words[0] >> 28) & 0xF
            guard mt == 0x3 else { return }
            let payload = decodeSysEx7UMP(words)
            guard !payload.isEmpty, let json = String(bytes: payload, encoding: .utf8) else { return }
            Task { await handle(json: json, baseURL: baseURL, getT: getPathTmpl, putT: putPathTmpl, transport: loop) }
        }
        try? loop.open()
        dispatchMain()
    }

    private static func handle(json: String, baseURL: URL, getT: String, putT: String, transport: LoopbackTransport) async {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prop = obj["propertyId"] as? String else { return }

        func path(_ tmpl: String, _ values: [String: String]) -> String {
            var s = tmpl
            for (k,v) in values { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
            return s
        }

        if prop == "persist.get.request" {
            let body = (obj["body"] as? [String: Any]) ?? [:]
            guard let coll = body["collection"] as? String, let id = body["id"] as? String else { return }
            let reqURL = baseURL.appendingPathComponent(path(getT, ["collection": coll, "id": id]))
            var req = URLRequest(url: reqURL)
            req.httpMethod = "GET"
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let env: [String: Any] = ["propertyId": "persist.get.result", "status": status, "body": (try? JSONSerialization.jsonObject(with: data)) ?? [:]]
                if let d = try? JSONSerialization.data(withJSONObject: env), let bytes = String(data: d, encoding: .utf8)?.utf8 {
                    for u in encodeSysEx7UMP(Array(bytes)) { try? transport.send(umpWords: u) }
                }
            } catch { }
        } else if prop == "persist.put.request" {
            let body = (obj["body"] as? [String: Any]) ?? [:]
            guard let coll = body["collection"] as? String, let id = body["id"] as? String else { return }
            let reqURL = baseURL.appendingPathComponent(path(putT, ["collection": coll, "id": id]))
            var req = URLRequest(url: reqURL)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: (body["body"] as? [String: Any]) ?? [:])
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let env: [String: Any] = ["propertyId": "persist.put.result", "status": status, "body": (try? JSONSerialization.jsonObject(with: data)) ?? [:]]
                if let d = try? JSONSerialization.data(withJSONObject: env), let bytes = String(data: d, encoding: .utf8)?.utf8 {
                    for u in encodeSysEx7UMP(Array(bytes)) { try? transport.send(umpWords: u) }
                }
            } catch { }
        }
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

