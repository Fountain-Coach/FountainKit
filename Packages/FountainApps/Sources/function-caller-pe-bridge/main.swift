import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MIDI2Transports

@main
struct FunctionCallerPEBridge {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let baseURL = URL(string: env["FC_BASE_URL"] ?? "http://127.0.0.1:8030")!
        var toolsPath = env["FC_TOOLS_PATH"] ?? "/function-caller/tools"
        var callPath = env["FC_CALL_PATH"] ?? "/function-caller/call"
        if let m = try? await loadMappingFromFacts(agentId: env["AGENT_ID"] ?? "fountain.coach/agent/function-caller/service") {
            if let mt = m["function.tools.request"], let o = mt["openapi"] as? [String: Any], let path = o["path"] as? String { toolsPath = path }
            if let mc = m["function.call.request"], let o = mc["openapi"] as? [String: Any], let path = o["path"] as? String { callPath = path }
        }
        FileHandle.standardError.write(Data("[function-caller-pe-bridge] base=\(baseURL.absoluteString)\n".utf8))

        let loop = LoopbackTransport()
        loop.onReceiveUMP = { words in
            let mt = (words[0] >> 28) & 0xF
            guard mt == 0x3 else { return }
            let payload = decodeSysEx7UMP(words)
            guard !payload.isEmpty, let json = String(bytes: payload, encoding: .utf8) else { return }
            Task { await handle(json: json, baseURL: baseURL, toolsPath: toolsPath, callPath: callPath, transport: loop) }
        }
        try? loop.open()
        dispatchMain()
    }

    private static func handle(json: String, baseURL: URL, toolsPath: String, callPath: String, transport: LoopbackTransport) async {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prop = obj["propertyId"] as? String else { return }

        if prop == "function.tools.request" {
            var url = baseURL.appendingPathComponent(toolsPath)
            if let body = obj["body"] as? [String: Any], let tags = body["tags"] as? [String], !tags.isEmpty {
                var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                comps?.queryItems = [URLQueryItem(name: "tags", value: tags.joined(separator: ","))]
                url = comps?.url ?? url
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let env: [String: Any] = ["propertyId": "function.tools.result", "status": status, "body": (try? JSONSerialization.jsonObject(with: data)) ?? [:]]
                if let d = try? JSONSerialization.data(withJSONObject: env), let bytes = String(data: d, encoding: .utf8)?.utf8 {
                    for u in encodeSysEx7UMP(Array(bytes)) { try? transport.send(umpWords: u) }
                }
            } catch { }
        } else if prop == "function.call.request" {
            let body = (obj["body"] as? [String: Any]) ?? [:]
            var req = URLRequest(url: baseURL.appendingPathComponent(callPath))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let env: [String: Any] = ["propertyId": "function.call.result", "status": status, "body": (try? JSONSerialization.jsonObject(with: data)) ?? [:]]
                if let d = try? JSONSerialization.data(withJSONObject: env), let bytes = String(data: d, encoding: .utf8)?.utf8 {
                    for u in encodeSysEx7UMP(Array(bytes)) { try? transport.send(umpWords: u) }
                }
            } catch { }
        }
    }
}

@MainActor private func loadMappingFromFacts(agentId: String) async throws -> [String: [String: Any]] {
    let env = ProcessInfo.processInfo.environment
    let corpus = env["AGENT_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "agents"
    let safeId = agentId.replacingOccurrences(of: "/", with: "|")
    let factsId = "facts:agent:\(safeId)"

    // Prefer local store-dump binary next to this executable; fall back to PATH.
    let exeURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
    let localStoreDump = exeURL.deletingLastPathComponent().appendingPathComponent("store-dump")
    let toolPath: String
    if FileManager.default.isExecutableFile(atPath: localStoreDump.path) {
        toolPath = localStoreDump.path
    } else {
        toolPath = "store-dump"
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [toolPath]
    var childEnv = env
    childEnv["CORPUS_ID"] = corpus
    childEnv["COLLECTION"] = "agent-facts"
    childEnv["ID"] = factsId
    proc.environment = childEnv
    let outPipe = Pipe()
    proc.standardOutput = outPipe
    let errPipe = Pipe()
    proc.standardError = errPipe

    do {
        try proc.run()
    } catch {
        return [:]
    }
    proc.waitUntilExit()
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    guard proc.terminationStatus == 0, !data.isEmpty else {
        return [:]
    }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    var map: [String: [String: Any]] = [:]
    if let blocks = obj["functionBlocks"] as? [[String: Any]] {
        for b in blocks {
            if let props = b["properties"] as? [[String: Any]] {
                for p in props {
                    if let id = p["id"] as? String, let mapsTo = p["mapsTo"] as? [String: Any] {
                        map[id] = mapsTo
                    }
                }
            }
        }
    }
    return map
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
