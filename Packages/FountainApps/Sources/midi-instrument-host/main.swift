import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MIDI2Transports
import FountainStoreClient
import MIDI2
import MIDI2CI
#if canImport(Network)
@preconcurrency import Network
#endif

// MIDI Instrument Host — CI/PE bridge
// Loads OpenAPI-derived facts from FountainStore for one or more agents,
// exposes them as MIDI‑CI PE properties, and routes PE GET/SET to HTTP.

// Route map box for safe cross-thread access
final class RouteBox: @unchecked Sendable {
    var map: [String: MIDIInstrumentHost.PropertyRoute] = [:]
    init() {}
}

@main
struct MIDIInstrumentHost {
    @MainActor static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["AGENT_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "agents"
        // Agents to load: comma-separated list; default to awareness+bootstrap for parity
        let agentsCSV = env["HOST_AGENTS"] ?? "fountain.coach/agent/baseline-awareness/service,fountain.coach/agent/bootstrap/service"
        let agents = agentsCSV.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let out = FileHandle.standardError
        out.write(Data("[midi-instrument-host] agents=\(agents.count) corpus=\(corpus)\n".utf8))

        // Route map boxed for safe mutation from timers and concurrent handlers
        let routes = RouteBox()
        var blocks: [[String: Any]] = []
        func refreshRoutes() async {
            var newMap: [String: PropertyRoute] = [:]
            blocks.removeAll(keepingCapacity: true)
            for agent in agents {
                if let f = await loadFacts(agentId: agent, corpus: corpus) {
                    if let fbs = f["functionBlocks"] as? [[String: Any]] { blocks.append(contentsOf: fbs) }
                    let pm = buildPropertyRoutes(agentId: agent, facts: f, env: env)
                    for (k, v) in pm { newMap[k] = v }
                }
            }
            routes.map = newMap
            out.write(Data("[midi-instrument-host] properties=\(routes.map.count) blocks=\(blocks.count)\n".utf8))
            // Print minimal auth hints
            for (key, route) in newMap {
                if let dj = route.descriptorJSON, let dd = dj.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: dd) as? [String: Any], let ex = obj["authHeaderExamples"] as? [String], !ex.isEmpty {
                    let hint = ex.joined(separator: "; ")
                    out.write(Data("[midi-instrument-host] auth \(key): \(hint)\n".utf8))
                }
            }
        }
        // Ensure facts are present before first refresh to avoid startup races
        await waitForFacts(agents: agents, corpus: corpus, timeoutMs: Int(env["HOST_FACTS_INITIAL_WAIT_MS"] ?? "4000") ?? 4000)
        await refreshRoutes()

        // Transports: loopback always; optional RTP fixed port and optional BLE Central
        var transmitters: [AnyTx] = []
        final class TxBox { var senders: [AnyTx]; init(_ s: [AnyTx]) { self.senders = s } }
        let txBox = TxBox([])
        let loop = LoopbackTransport()
        loop.onReceiveUMP = { words in handleUMP(words, routes: routes, tx: txBox.senders) }
        try? loop.open()
        transmitters.append(AnyTx { words in try? loop.send(umpWords: words) })

        // Default RTP fixed port 5868 unless explicitly disabled with HOST_RTP_PORT=0
        let rtpPort: UInt16? = {
            if let s = env["HOST_RTP_PORT"], let v = Int(s) { return v > 0 ? UInt16(v) : nil }
            return 5868
        }()
        if let p = rtpPort {
            let r = RTPMidiSession(localName: "FountainHost", enableDiscovery: true, enableCINegotiation: true, listenPort: p)
            r.onReceiveUMP = { words in handleUMP(words, routes: routes, tx: txBox.senders) }
            try? r.open()
            if let actual = r.port { out.write(Data("[midi-instrument-host] RTP listening :\(actual)\n".utf8)) }
            transmitters.append(AnyTx { words in try? r.send(umpWords: words) })
        }
        #if canImport(CoreBluetooth)
        if (env["HOST_BLE"] ?? "1") != "0" {
            if #available(macOS 12.0, *) {
                let filt = env["HOST_BLE_TARGET"]
                let ble = BLEMidiTransport(targetNameContains: filt)
                ble.onReceiveUMP = { words in handleUMP(words, routes: routes, tx: txBox.senders) }
                try? ble.open()
                transmitters.append(AnyTx { words in try? ble.send(umpWords: words) })
                out.write(Data("[midi-instrument-host] BLE Central enabled (filter=\(filt ?? "<any>"))\n".utf8))
            }
        }
        if (env["HOST_BLE_PERIPH"] ?? "0") != "0" {
            if #available(macOS 12.0, *) {
                let name = env["HOST_BLE_PERIPH_NAME"] ?? "FountainHost"
                let blep = BLEMidiPeripheralTransport(advertisedName: name)
                blep.onReceiveUMP = { words in handleUMP(words, routes: routes, tx: txBox.senders) }
                try? blep.open()
                transmitters.append(AnyTx { words in try? blep.send(umpWords: words) })
                out.write(Data("[midi-instrument-host] BLE Peripheral advertising as \(name)\n".utf8))
            }
        }
        #endif
        // Save transmitters for replies
        txBox.senders = transmitters
        // Optional local health HTTP. Default OFF (0) per "no local HTTP" policy.
        let healthPort = Int(env["HOST_HEALTH_PORT"] ?? "0") ?? 0
        if healthPort > 0 {
            if #available(macOS 12.0, *) { _ = startHealthServer(String(healthPort)) }
            out.write(Data("[midi-instrument-host] health :\(healthPort) (/ready,/live,/metrics)\n".utf8))
        }
        out.write(Data("[midi-instrument-host] health :\(healthPort) (/ready,/live,/metrics)\n".utf8))
        // Facts hot-reload (poll) — default 10s
        let pollSec = Int(env["HOST_FACTS_POLL_SEC"] ?? "10") ?? 10
        if pollSec > 0 {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .seconds(pollSec), repeating: .seconds(pollSec))
            timer.setEventHandler { Task { await refreshRoutes() } }
            timer.resume()
        }
        // Keep process alive in async context
        while true { try? await Task.sleep(nanoseconds: 1_000_000_000) }
    }

    // MARK: - Message handling
    nonisolated static func handleUMP(_ words: [UInt32], routes: RouteBox, tx: [AnyTx]) {
        guard !words.isEmpty else { return }
        // Extract SysEx7 payload; UMP type 3x are SysEx7 packets
        let mt = (words[0] >> 28) & 0xF
        guard mt == 0x3 else { return }
        let payload = unpackSysEx7(words)
        guard let env = safeDecodeCI(sysEx7: payload) else { return }
        if case .propertyExchange(let pe) = env.body {
            let map = routes.map
            Task { await handlePE(pe, propertyMap: map, group: UInt8((words[0] >> 24) & 0xF), tx: tx) }
        }
    }

    nonisolated static func handlePE(_ pe: MidiCiPropertyExchangeBody, propertyMap: [String: PropertyRoute], group: UInt8, tx: [AnyTx]) async {
        let reqId = pe.requestId
        let cmd = pe.command
        let reply: MidiCiPropertyExchangeBody
        switch cmd {
        case .get:
            // Enriched descriptors from routes (facts‑derived)
            var props: [[String: Any]] = []
            for key in propertyMap.keys.sorted() {
                guard let r = propertyMap[key] else { continue }
                var desc: [String: Any] = [
                    "name": key,
                    "agent": r.agent,
                    "method": r.method,
                    "path": r.path
                ]
                if let b = r.bodyKind { desc["bodyKind"] = b }
                desc["readable"] = (r.method == "GET")
                // Any known body kind implies writability (json, text, binary, multipart)
                desc["writable"] = (r.bodyKind != nil)
                if let dj = r.descriptorJSON, let dd = dj.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: dd) { desc["descriptor"] = obj }
                if let s = r.sampleJSON, let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) {
                    desc["samples"] = ["request": obj]
                }
                props.append(desc)
            }
            let obj: [String: Any] = ["properties": props]
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            reply = MidiCiPropertyExchangeBody(command: .getReply, requestId: reqId, encoding: .json, header: [:], data: [UInt8](data))
        case .set:
            var results: [[String: Any]] = []
            if let obj = try? JSONSerialization.jsonObject(with: Data(pe.data)) as? [String: Any], let arr = obj["properties"] as? [[String: Any]] {
                for p in arr {
                    guard let name = p["name"] as? String, let route = propertyMap[name] else { continue }
                    let body = (p["value"] as? [String: Any]) ?? [:]
                    let (status, data, contentType) = await route.invoke(with: body)
                    var one: [String: Any] = ["name": name, "status": status]
                    if let d = data {
                        if let ct = contentType, ct.contains("application/json"), let obj = try? JSONSerialization.jsonObject(with: d) {
                            one["body"] = obj
                        } else if let s = String(data: d, encoding: .utf8), !s.isEmpty {
                            one["body"] = s
                        } else {
                            one["bodyBase64"] = d.base64EncodedString()
                        }
                    }
                    results.append(one)
                }
            }
            let obj: [String: Any] = ["properties": results]
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            reply = MidiCiPropertyExchangeBody(command: .notify, requestId: reqId, encoding: .json, header: [:], data: [UInt8](data))
        default:
            let data = Data("{}".utf8)
            reply = MidiCiPropertyExchangeBody(command: .notify, requestId: reqId, encoding: .json, header: [:], data: [UInt8](data))
        }
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(reply))
        let umps = packSysEx7UMP(group: group, bytes: env.sysEx7Payload())
        for u in umps { for t in tx { t.sendOne(u) } }
    }

    // MARK: - Facts → routes
    struct PropertyRoute {
        var id: String
        var agent: String
        var method: String
        var path: String
        var bodyKind: String? // "json" | "text" | "binary" | "multipart" | nil
        var baseURL: URL
        var sampleJSON: String?
        var descriptorJSON: String?
        var handler: ((([String: Any]) async -> (Int, Data?, String?))?)
        func invoke(with input: [String: Any]) async -> (Int, Data?, String?) {
            if let h = handler {
                return await h(input)
            }
            let pathFinal = substitute(pathTmpl: path, with: input)
            var comps = URLComponents(url: baseURL.appendingPathComponent(pathFinal), resolvingAgainstBaseURL: false)!
            var req = URLRequest(url: comps.url!)
            req.httpMethod = method
            if let q = input["query"] as? [String: Any] {
                comps.queryItems = q.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
                req.url = comps.url
            }
            switch (bodyKind ?? "") {
            case "json":
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload = input["body"] ?? input
                if let data = try? JSONSerialization.data(withJSONObject: payload) { req.httpBody = data }
                else if let s = sampleJSON { req.httpBody = Data(s.utf8) }
            case "text":
                req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                if let t = input["text"] as? String { req.httpBody = Data(t.utf8) }
                else if let t = input["body"] as? String { req.httpBody = Data(t.utf8) }
                else if let s = sampleJSON { req.httpBody = decodeJSONStringToUTF8Data(s) }
            case "binary":
                let ct = (input["contentType"] as? String) ?? "application/octet-stream"
                req.setValue(ct, forHTTPHeaderField: "Content-Type")
                if let b64 = input["bodyBase64"] as? String, let d = Data(base64Encoded: b64) {
                    req.httpBody = d
                } else if let uri = input["uri"] as? String, let d = loadDataFromURI(uri) {
                    req.httpBody = d
                }
            case "multipart":
                let boundary = "----FountainHostBoundary\(Int.random(in: 0..<Int.max))"
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                if let parts = input["parts"] as? [String: Any] {
                    req.httpBody = buildMultipartBody(boundary: boundary, parts: parts)
                }
            default:
                break
            }
            // Auth headers (descriptor‑driven + SecretStore via FountainStore)
            var hintedHeaders: [String] = []
            if let dj = descriptorJSON, let dd = dj.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: dd) as? [String: Any],
               let arr = obj["authHeaders"] as? [String] {
                hintedHeaders = arr
            }
            if let secretHeaders = await MIDIInstrumentHost.loadSecrets(agentId: agent) {
                // If hints provided, apply only hinted headers; otherwise apply all provided headers
                if !hintedHeaders.isEmpty {
                    for name in hintedHeaders {
                        if let v = secretHeaders[name] { req.setValue(v, forHTTPHeaderField: name) }
                    }
                } else {
                    for (k, v) in secretHeaders { req.setValue(v, forHTTPHeaderField: k) }
                }
            }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let ct = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
                return (status, data, ct)
            } catch {
                return (0, nil, nil)
            }
        }
        // No env-based secret resolution — secrets come from SecretStore (FountainStore-backed)
    }

    static func buildPropertyRoutes(agentId: String, facts: [String: Any], env: [String: String]) -> [String: PropertyRoute] {
        let safe = agentId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "-", with: "_")
        let key = "AGENT_BASE_URL_\(safe.uppercased())"
        let baseStr = env[key] ?? env["AGENT_BASE_URL"] ?? "http://127.0.0.1:8020"
        var base = URL(string: baseStr) ?? URL(string: "http://127.0.0.1:8020")!
        var map: [String: PropertyRoute] = [:]
        if let blocks = facts["functionBlocks"] as? [[String: Any]] {
            for b in blocks {
                for p in (b["properties"] as? [[String: Any]] ?? []) {
                    guard let id = p["id"] as? String, let mt = p["mapsTo"] as? [String: Any], let oa = mt["openapi"] as? [String: Any], let path = oa["path"] as? String else { continue }
                    let method = (oa["method"] as? String ?? "GET").uppercased()
                    let bodyKind = oa["body"] as? String
                    var sampleJSON: String? = nil
                    if let s = (p["samples"] as? [String: Any])?["request"], let d = try? JSONSerialization.data(withJSONObject: s), let s = String(data: d, encoding: .utf8) { sampleJSON = s }
                    var descriptorJSON: String? = nil
                    if let d = p["descriptor"], let data = try? JSONSerialization.data(withJSONObject: d), let s = String(data: data, encoding: .utf8) {
                        descriptorJSON = s
                        // If no explicit AGENT_BASE_URL is provided, allow descriptor to hint serverURL
                        if env[key] == nil && env["AGENT_BASE_URL"] == nil,
                           let dobj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let serverURL = dobj["serverURL"] as? String,
                           let hinted = URL(string: serverURL) {
                            base = hinted
                        }
                    }
                    // Use unique name combining agent and id to avoid collisions
                    let name = "\(agentId)|\(id)"
                    map[name] = PropertyRoute(id: name, agent: agentId, method: method, path: path, bodyKind: bodyKind, baseURL: base, sampleJSON: sampleJSON, descriptorJSON: descriptorJSON, handler: nil)
                }
            }
        }
        // Attach internal Facts‑Factory instrument routes when enabled
        if (env["HOST_ENABLE_FACTS_FACTORY"] ?? "1") != "0" {
            let ffAgent = env["FACTS_FACTORY_AGENT_ID"] ?? "fountain.coach/agent/facts-factory/service"
            let ffName = "\(ffAgent)|facts.from_openapi.submit"
            let descriptor: [String: Any] = [
                "request": [
                    "schema": [
                        "type": "object",
                        "required": ["agentId"],
                        "properties": [
                            "agentId": ["type": "string"],
                            "corpusId": ["type": "string"],
                            "seed": ["type": "boolean"],
                            "openapi": ["type": "object"],
                            "specURL": ["type": "string"]
                        ]
                    ]
                ]
            ]
            let descJSON = (try? JSONSerialization.data(withJSONObject: descriptor)).flatMap { String(data: $0, encoding: .utf8) }
            func handler(_ input: [String: Any]) async -> (Int, Data?, String?) {
                let env = ProcessInfo.processInfo.environment
                let corpus = (input["corpusId"] as? String) ?? env["AGENT_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "agents"
                guard let agentId = input["agentId"] as? String, !agentId.isEmpty else {
                    let msg: [String: Any] = ["error": "invalid_request", "message": "agentId required"]
                    let d = try? JSONSerialization.data(withJSONObject: msg)
                    return (400, d, "application/json")
                }
                // Prepare spec data
                var openapiData: Data? = nil
                if let o = input["openapi"] {
                    if let obj = o as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: obj) { openapiData = d }
                    else if let s = o as? String { openapiData = Data(s.utf8) }
                }
                if openapiData == nil, let urlStr = input["specURL"] as? String, let url = URL(string: urlStr) {
                    if let (d, _) = try? await URLSession.shared.data(from: url) { openapiData = d }
                }
                guard let specData = openapiData else {
                    let msg: [String: Any] = ["error": "invalid_request", "message": "openapi or specURL required"]
                    let d = try? JSONSerialization.data(withJSONObject: msg)
                    return (400, d, "application/json")
                }
                // Write to tmp file
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let tmpDir = cwd.appendingPathComponent(".fountain/tmp", isDirectory: true)
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let looksLikeYAML = String(data: specData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("openapi:") ?? false
                let ext = looksLikeYAML ? "yaml" : "json"
                let tmpSpec = tmpDir.appendingPathComponent("ff-incoming-\(UUID().uuidString).\(ext)")
                do { try specData.write(to: tmpSpec) } catch {
                    let msg: [String: Any] = ["error": "io_error", "message": "failed to write tmp spec: \(error.localizedDescription)"]
                    let d = try? JSONSerialization.data(withJSONObject: msg)
                    return (500, d, "application/json")
                }
                // Call generator CLI
                let doSeed = (input["seed"] as? Bool) ?? true
                let task = Process()
                task.launchPath = "/usr/bin/env"
                var args = ["swift", "run", "--package-path", "Packages/FountainTooling", "-c", "debug", "openapi-to-facts", tmpSpec.path, "--agent-id", agentId, "--allow-tools-only"]
                if doSeed { args.append("--seed") }
                task.arguments = args
                var envp = env
                envp["CORPUS_ID"] = corpus
                task.environment = envp
                let outPipe = Pipe(); let errPipe = Pipe()
                task.standardOutput = outPipe; task.standardError = errPipe
                do { try task.run() } catch {
                    let msg: [String: Any] = ["error": "spawn_error", "message": error.localizedDescription]
                    let d = try? JSONSerialization.data(withJSONObject: msg)
                    return (500, d, "application/json")
                }
                task.waitUntilExit()
                let code = task.terminationStatus
                let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
                if code != 0 {
                    let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let s = String(data: stderr, encoding: .utf8) ?? ""
                    let msg: [String: Any] = ["error": "generator_failed", "message": s]
                    let d = try? JSONSerialization.data(withJSONObject: msg)
                    return (500, d, "application/json")
                }
                return (200, stdout, "application/json")
            }
            map[ffName] = PropertyRoute(
                id: ffName,
                agent: ffAgent,
                method: "POST",
                path: "/agent-facts/from-openapi",
                bodyKind: "json",
                baseURL: URL(string: "http://localhost")!,
                sampleJSON: nil,
                descriptorJSON: descJSON,
                handler: handler
            )
        }
        // Attach internal handlers for MPE Pad instrument (agent: fountain.coach/agent/mpe-pad/service)
        if agentId == "fountain.coach/agent/mpe-pad/service" {
            func setHandler(_ key: String, _ h: @escaping ([String: Any]) async -> (Int, Data?, String?)) {
                let name = "\(agentId)|\(key)"
                if var r = map[name] { r.handler = h; map[name] = r }
            }
            setHandler("mpe.open") { input in
                let port = (input["port"] as? Int).map { UInt16($0) } ?? 5869
                let bend = (input["bendRange"] as? Int).map { UInt8($0) } ?? 48
                await MPEManager.shared.open(port: port, bendRange: bend)
                return (200, Data("{}".utf8), "application/json")
            }
            setHandler("mpe.note") { input in
                let note = UInt8((input["note"] as? Int) ?? 60)
                let vel = UInt8((input["velocity"] as? Int) ?? 96)
                let on = (input["on"] as? Bool) ?? true
                if on { await MPEManager.shared.noteOn(note: note, velocity: vel) }
                else { await MPEManager.shared.noteOff(note: note, velocity: vel) }
                return (200, Data("{}".utf8), "application/json")
            }
            setHandler("mpe.pitchbend") { input in
                let v = UInt16((input["value14"] as? Int) ?? 8192)
                await MPEManager.shared.pitchBend(value14: v)
                return (200, Data("{}".utf8), "application/json")
            }
            setHandler("mpe.polyaftertouch") { input in
                let note = UInt8((input["note"] as? Int) ?? 60)
                let p = UInt8((input["pressure"] as? Int) ?? 0)
                await MPEManager.shared.polyAftertouch(note: note, pressure: p)
                return (200, Data("{}".utf8), "application/json")
            }
        }
        return map
    }

    // MARK: - MPE manager (RTP-only; no CoreMIDI)
    actor MPEManager {
        static let shared = MPEManager()
        private var rtp: RTPMidiSession?
        private var group: UInt8 = 0
        private var channel: UInt8 = 2 // first member channel (lower zone)
        private var bendRange: UInt8 = 48
        func open(port: UInt16, bendRange: UInt8) async {
            do { try await close() } catch {}
            let s = RTPMidiSession(localName: "FountainHost MPE", enableDiscovery: true, enableCINegotiation: true, listenPort: port)
            try? s.open()
            rtp = s; self.bendRange = bendRange
            for ch in 2...16 { sendRPNPitchBendRange(channel: UInt8(ch), semitones: bendRange) }
        }
        func close() async throws { try rtp?.close(); rtp = nil }
        private func send(_ words: [UInt32]) { try? rtp?.send(umps: words.chunked(4)) }
        private func w(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) -> UInt32 {
            let mt: UInt32 = 0x2 << 28
            let grp: UInt32 = UInt32(group & 0x0F) << 24
            let st: UInt32 = UInt32(status)
            let b1: UInt32 = UInt32(d1)
            let b2: UInt32 = UInt32(d2)
            return mt | grp | (st << 16) | (b1 << 8) | b2
        }
        private func cc(_ controller: UInt8, _ value: UInt8, channel: UInt8) -> UInt32 { w(0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F) }
        private func sendRPNPitchBendRange(channel: UInt8, semitones: UInt8) {
            send([cc(101, 0, channel: channel), cc(100, 0, channel: channel), cc(6, semitones, channel: channel), cc(38, 0, channel: channel), cc(101, 127, channel: channel), cc(100, 127, channel: channel)])
        }
        func noteOn(note: UInt8, velocity: UInt8) async { send([w(0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F)]) }
        func noteOff(note: UInt8, velocity: UInt8) async { send([w(0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F)]) }
        func pitchBend(value14: UInt16) async {
            let lsb = UInt8(value14 & 0x7F); let msb = UInt8((value14 >> 7) & 0x7F)
            send([w(0xE0 | (channel & 0x0F), lsb, msb)])
        }
        func polyAftertouch(note: UInt8, pressure: UInt8) async { send([w(0xA0 | (channel & 0x0F), note & 0x7F, pressure & 0x7F)]) }
    }

    // MARK: - Store + helpers
    @MainActor static func waitForFacts(agents: [String], corpus: String, timeoutMs: Int) async {
        let start = Date().timeIntervalSince1970
        while true {
            var missing: [String] = []
            for a in agents {
                if await loadFacts(agentId: a, corpus: corpus) == nil { missing.append(a) }
            }
            if missing.isEmpty { return }
            let elapsed = Int((Date().timeIntervalSince1970 - start) * 1000)
            if elapsed >= timeoutMs { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
    @MainActor static func loadFacts(agentId: String, corpus: String) async -> [String: Any]? {
        let store: FountainStoreClient = {
            if let dir = ProcessInfo.processInfo.environment["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        let safeId = agentId.replacingOccurrences(of: "/", with: "|")
        let keys = ["facts:agent:\(safeId)", "facts:agent:\(agentId)"]
        for key in keys {
            if let data = try? await store.getDoc(corpusId: corpus, collection: "agent-facts", id: key), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            // Fallback to local seed image (app-like startup when store empty)
            let seedRel = "Dist/store-seeds/seed-v1/agents/agent-facts/\(key).json"
            let seedURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(seedRel)
            if let data = try? Data(contentsOf: seedURL), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    @MainActor static func loadSecrets(agentId: String) async -> [String: String]? {
        // Secrets are stored in FountainStore under corpus 'secrets' by default.
        let env = ProcessInfo.processInfo.environment
        let corpus = env["SECRETS_CORPUS_ID"] ?? "secrets"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        func keyFor(_ agent: String) -> String {
            let safe = agent.replacingOccurrences(of: "/", with: "|")
            return "secret:agent:\(safe)"
        }
        let keys = [keyFor(agentId), "secret:agent:\(agentId)", "secret:default"]
        for key in keys {
            if let data = try? await store.getDoc(corpusId: corpus, collection: "secrets", id: key),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let headers = obj["headers"] as? [String: String] { return headers }
                // Fallback: treat flat object as header map
                var map: [String: String] = [:]
                for (k, v) in obj { if let s = v as? String { map[k] = s } }
                if !map.isEmpty { return map }
            }
        }
        return nil
    }

    static func substitute(pathTmpl: String, with body: [String: Any]) -> String {
        var s = pathTmpl
        let regex = try! NSRegularExpression(pattern: "\\{([a-zA-Z0-9_.-]+)\\}")
        let matches = regex.matches(in: pathTmpl, range: NSRange(location: 0, length: pathTmpl.utf16.count))
        for m in matches.reversed() {
            let r = m.range(at: 1)
            let start = pathTmpl.index(pathTmpl.startIndex, offsetBy: r.location)
            let end = pathTmpl.index(start, offsetBy: r.length)
            let key = String(pathTmpl[start..<end])
            let val = (body[key] as? CustomStringConvertible)?.description ?? ""
            let whole = m.range(at: 0)
            let ws = pathTmpl.index(pathTmpl.startIndex, offsetBy: whole.location)
            let we = pathTmpl.index(ws, offsetBy: whole.length)
            s.replaceSubrange(ws..<we, with: val)
        }
        return s
    }

    // MIDI-CI safe decode
    static func safeDecodeCI(sysEx7 bytes: [UInt8]) -> MidiCiEnvelope? {
        guard bytes.count >= 7, bytes.first == 0xF0, bytes.last == 0xF7 else { return nil }
        let manuf = bytes[1]
        guard manuf == 0x7E || manuf == 0x7F else { return nil }
        guard bytes.count > 4, bytes[3] == 0x0D else { return nil }
        return try? MidiCiEnvelope(sysEx7Payload: bytes)
    }

    // UMP SysEx7 pack/unpack
    static func unpackSysEx7(_ words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i + 1 < words.count {
            let w1 = words[i], w2 = words[i+1]
            if ((w1 >> 28) & 0xF) != 0x3 { break }
            let n = Int((w1 >> 16) & 0xF)
            let bytes: [UInt8] = [
                UInt8((w1 >> 8) & 0xFF), UInt8(w1 & 0xFF),
                UInt8((w2 >> 24) & 0xFF), UInt8((w2 >> 16) & 0xFF), UInt8((w2 >> 8) & 0xFF), UInt8(w2 & 0xFF)
            ]
            out.append(contentsOf: bytes.prefix(n))
            i += 2
        }
        return out
    }
    static func packSysEx7UMP(group: UInt8, bytes: [UInt8]) -> [[UInt32]] {
        if bytes.isEmpty { return [] }
        var umps: [[UInt32]] = []
        var idx = 0
        var first = true
        while idx < bytes.count {
            let remain = bytes.count - idx
            let n = min(6, remain)
            let status: UInt8 = (first && n == remain) ? 0x0 : (first ? 0x1 : (n == remain ? 0x3 : 0x2))
            var chunk = Array(bytes[idx..<(idx + n)])
            while chunk.count < 6 { chunk.append(0) }
            let w1 = (UInt32(0x3) << 28) | (UInt32(group & 0x0F) << 24) | (UInt32(status) << 20) | (UInt32(n) << 16) | (UInt32(chunk[0]) << 8) | UInt32(chunk[1])
            let w2 = (UInt32(chunk[2]) << 24) | (UInt32(chunk[3]) << 16) | (UInt32(chunk[4]) << 8) | UInt32(chunk[5])
            umps.append([w1, w2])
            idx += n
            first = false
        }
        return umps
    }
}

// Tx aggregator
struct AnyTx: @unchecked Sendable {
    let sendOne: (/*words*/[UInt32]) -> Void
}

// no static shared state — we pass Tx lists through closures

#if canImport(Network)
@available(macOS 12.0, *)
private func startHealthServer(_ portStr: String?) -> NWListener? {
    let portInt = Int(portStr ?? "") ?? 8787
    guard let p = NWEndpoint.Port(rawValue: UInt16(portInt)) else { return nil }
    let listener = try? NWListener(using: .tcp, on: p)
    listener?.stateUpdateHandler = { _ in }
    listener?.newConnectionHandler = { conn in
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, _ in
            // Always return 200 ok with tiny body
            let body = "ok\n".data(using: .utf8) ?? Data()
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var resp = Data(headers.utf8); resp.append(body)
            conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
        }
    }
    listener?.start(queue: .global())
    return listener
}
#endif
private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0+size, count)]) }
    }
}

// MARK: - HTTP helpers for body kinds
@inline(__always) private func decodeJSONStringToUTF8Data(_ s: String) -> Data? {
    // s is a JSON-encoded value; try to decode to String then return raw bytes
    if let d = s.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: d) {
        if let str = any as? String { return Data(str.utf8) }
    }
    return s.data(using: .utf8)
}

private func loadDataFromURI(_ uri: String) -> Data? {
    if let url = URL(string: uri), url.scheme?.lowercased() == "file" {
        return try? Data(contentsOf: url)
    }
    // Treat as path
    let url = URL(fileURLWithPath: uri)
    return try? Data(contentsOf: url)
}

private func buildMultipartBody(boundary: String, parts: [String: Any]) -> Data {
    var body = Data()
    let boundaryLine = "--\(boundary)\r\n"
    for (name, val) in parts {
        body.append(Data(boundaryLine.utf8))
        if let s = val as? String {
            let headers = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            body.append(Data(headers.utf8))
            body.append(Data(s.utf8))
            body.append(Data("\r\n".utf8))
        } else if let obj = val as? [String: Any] {
            let ct = (obj["contentType"] as? String) ?? "application/octet-stream"
            let filename = (obj["filename"] as? String) ?? name
            var data: Data? = nil
            if let b64 = obj["bodyBase64"] as? String { data = Data(base64Encoded: b64) }
            if data == nil, let uri = obj["uri"] as? String { data = loadDataFromURI(uri) }
            if let text = obj["value"] as? String { // explicit text value
                let headers = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                body.append(Data(headers.utf8))
                body.append(Data(text.utf8))
                body.append(Data("\r\n".utf8))
            } else if let d = data {
                let headers = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(ct)\r\n\r\n"
                body.append(Data(headers.utf8))
                body.append(d)
                body.append(Data("\r\n".utf8))
            } else {
                // Fallback empty field
                let headers = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                body.append(Data(headers.utf8))
                body.append(Data("\r\n".utf8))
            }
        } else {
            // Unknown shape, send empty field
            let headers = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            body.append(Data(headers.utf8))
            body.append(Data("\r\n".utf8))
        }
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return body
}
