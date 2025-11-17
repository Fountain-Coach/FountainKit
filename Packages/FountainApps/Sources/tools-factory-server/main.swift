import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainStoreClient
import ToolsFactoryService
import FountainRuntime
import LauncherSignature

let env = ProcessInfo.processInfo.environment
if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

let manifestURL = URL(fileURLWithPath: "tools.json")
let manifest = (try? ToolManifest.load(from: manifestURL)) ?? ToolManifest(image: .init(name: "", tarball: "", sha256: "", qcow2: "", qcow2_sha256: ""), tools: [:], operations: [])
let corpusId = env["TOOLS_FACTORY_CORPUS_ID"] ?? env["DEFAULT_CORPUS_ID"] ?? "tools-factory"

let svc: FountainStoreClient = {
    if let dir = env["FOUNTAINSTORE_DIR"], !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let url: URL
        if dir.hasPrefix("~") {
            url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
        } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
        if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
            return FountainStoreClient(client: disk)
        }
    }
    return FountainStoreClient(client: EmbeddedFountainStoreClient())
}()
Task {
    await svc.ensureCollections(corpusId: corpusId)
    try? await publishFunctions(manifest: manifest, corpusId: corpusId, service: svc)
    // Fallback serves metrics, the spec, and facts-from-openapi helper.
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        // POST /agent-facts/from-openapi — generate and optionally seed
        if req.method == "POST" && req.path == "/agent-facts/from-openapi" {
            // Expected JSON body: { agentId: String, corpusId?: String, seed?: Bool, openapi?: Object|String, specURL?: String }
            guard !req.body.isEmpty,
                  let root = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let agentId = root["agentId"] as? String, !agentId.isEmpty else {
                let msg = ["error": "invalid_request", "message": "agentId required, body must be JSON"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            let corpus = (root["corpusId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let doSeed = (root["seed"] as? Bool) ?? true
            var openapiData: Data? = nil
            // Prefer explicit openapi object/string in request
            if let o = root["openapi"] {
                if let obj = o as? [String: Any] {
                    openapiData = try? JSONSerialization.data(withJSONObject: obj, options: [])
                } else if let s = o as? String { openapiData = Data(s.utf8) }
            }
            // Or fetch from URL
            if openapiData == nil, let urlStr = root["specURL"] as? String, let url = URL(string: urlStr) {
                if let (data, _) = try? await URLSession.shared.data(from: url) { openapiData = data }
            }
            guard let specData = openapiData else {
                let msg = ["error": "invalid_request", "message": "openapi or specURL required"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            // Write to a temp file with appropriate extension
            let tmpDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent(".fountain/tmp", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let looksLikeYAML = String(data: specData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("openapi:") ?? false
            let ext = looksLikeYAML ? "yaml" : "json"
            let tmpSpec = tmpDir.appendingPathComponent("incoming-\(UUID().uuidString).\(ext)")
            do { try specData.write(to: tmpSpec) } catch {
                let msg = ["error": "io_error", "message": "failed to write tmp spec: \(error.localizedDescription)"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 500, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            // Invoke the generator CLI and capture stdout (facts JSON)
            let task = Process()
            task.launchPath = "/usr/bin/env"
            var args = ["swift", "run", "--package-path", "Packages/FountainTooling", "-c", "debug", "openapi-to-facts", tmpSpec.path, "--agent-id", agentId, "--allow-tools-only"]
            if doSeed { args.append("--seed") }
            task.arguments = args
            var envp = ProcessInfo.processInfo.environment
            if let corpus, !corpus.isEmpty { envp["CORPUS_ID"] = corpus }
            // Preserve FOUNTAINSTORE_DIR if set so seeding goes to the same store this server uses
            task.environment = envp
            let outPipe = Pipe(); let errPipe = Pipe()
            task.standardOutput = outPipe; task.standardError = errPipe
            do {
                try task.run()
            } catch {
                let msg = ["error": "spawn_error", "message": "failed to start generator: \(error.localizedDescription)"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 500, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            task.waitUntilExit()
            let status = task.terminationStatus
            let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
            if status != 0 {
                let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: stderrData, encoding: .utf8) ?? ""
                let msg = ["error": "generator_failed", "message": errStr]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 500, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            // Return the generator stdout (facts JSON)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: stdoutData)
        }
        // POST /agent-secrets — upsert SecretStore headers for an agent (gated)
        if req.method == "POST" && req.path == "/agent-secrets" {
            // Gate: disabled unless TOOLS_FACTORY_ALLOW_SECRET_UPSERT=1
            let allow = (env["TOOLS_FACTORY_ALLOW_SECRET_UPSERT"] ?? "0") == "1"
            if allow == false {
                let msg = ["error": "forbidden", "message": "secret upsert disabled"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 403, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            // Require admin key if set
            if let admin = env["TOOLS_FACTORY_ADMIN_KEY"], !admin.isEmpty {
                let provided = req.headers["X-Admin-Key"] ?? req.headers["Authorization"]
                if provided != admin && provided != "Bearer \(admin)" {
                    let msg = ["error": "unauthorized", "message": "invalid admin key"]
                    let body = try? JSONSerialization.data(withJSONObject: msg)
                    return HTTPResponse(status: 401, headers: ["Content-Type": "application/json"], body: body ?? Data())
                }
            }
            // Body: { agentId: string, corpusId?: string="secrets", headers: { <HeaderName>: <Value>, ... } }
            guard !req.body.isEmpty,
                  let root = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let agentId = root["agentId"] as? String, !agentId.isEmpty else {
                let msg = ["error": "invalid_request", "message": "agentId required, body must be JSON"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            let secretsCorpus = (root["corpusId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let corpus = (secretsCorpus?.isEmpty == false) ? secretsCorpus! : "secrets"
            let safeId = agentId.replacingOccurrences(of: "/", with: "|")
            let key = "secret:agent:\(safeId)"
            var headers: [String: String] = [:]
            if let h = root["headers"] as? [String: Any] {
                for (k, v) in h { if let s = v as? String { headers[k] = s } }
            }
            guard headers.isEmpty == false else {
                let msg = ["error": "invalid_request", "message": "headers required (map of header → value)" ]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            let payload = ["headers": headers]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                do {
                    try await svc.putDoc(corpusId: corpus, collection: "secrets", id: key, body: data)
                    let ok = ["ok": true, "id": key, "corpus": corpus]
                    let out = try? JSONSerialization.data(withJSONObject: ok)
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: out ?? Data())
                } catch {
                    let err = ["error": "store_error", "message": String(describing: error)]
                    let out = try? JSONSerialization.data(withJSONObject: err)
                    return HTTPResponse(status: 500, headers: ["Content-Type": "application/json"], body: out ?? Data())
                }
            }
            return HTTPResponse(status: 500)
        }
        // GET /agent-secrets/missing?agentId=...&factsCorpusId=agents&secretsCorpusId=secrets
        if req.method == "GET" && req.path == "/agent-secrets/missing" {
            // Fallback: parse query from the raw path (req.path excludes query; use req.raw if available)
            func parseQuery(_ raw: String) -> [String: String] {
                guard let qm = raw.firstIndex(of: "?") else { return [:] }
                let q = raw[raw.index(after: qm)...]
                var out: [String: String] = [:]
                for pair in q.split(separator: "&") {
                    let parts = pair.split(separator: "=", maxSplits: 1)
                    if parts.count == 2, let k = String(parts[0]).removingPercentEncoding, let v = String(parts[1]).removingPercentEncoding { out[k] = v }
                }
                return out
            }
            let raw = req.headers["X-Request-Target"] ?? (req.headers[":path"] ?? req.path)
            let q = parseQuery(raw)
            guard let agentId = q["agentId"], !agentId.isEmpty else {
                let msg = ["error": "invalid_request", "message": "agentId required"]
                let body = try? JSONSerialization.data(withJSONObject: msg)
                return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: body ?? Data())
            }
            let factsCorpus = q["factsCorpusId"] ?? "agents"
            let secretsCorpus = q["secretsCorpusId"] ?? "secrets"
            // Compute required headers from facts
            var required: Set<String> = []
            do {
                let safe = agentId.replacingOccurrences(of: "/", with: "|")
                let keys = ["facts:agent:\(safe)", "facts:agent:\(agentId)"]
                var facts: [String: Any]? = nil
                for k in keys {
                    if let data = try? await svc.getDoc(corpusId: factsCorpus, collection: "agent-facts", id: k), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { facts = obj; break }
                }
                if let facts, let blocks = facts["functionBlocks"] as? [[String: Any]] {
                    for b in blocks {
                        for p in (b["properties"] as? [[String: Any]] ?? []) {
                            if let d = p["descriptor"] as? [String: Any], let hs = d["authHeaders"] as? [String] { for h in hs { required.insert(h) } }
                        }
                    }
                }
            }
            var present: [String: String] = [:]
            do {
                let safe = agentId.replacingOccurrences(of: "/", with: "|")
                let keys = ["secret:agent:\(safe)", "secret:agent:\(agentId)", "secret:default"]
                for k in keys {
                    if let data = try? await svc.getDoc(corpusId: secretsCorpus, collection: "secrets", id: k), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let h = obj["headers"] as? [String: String] { present = h; break }
                        var map: [String: String] = [:]
                        for (kk, vv) in obj { if let s = vv as? String { map[kk] = s } }
                        if !map.isEmpty { present = map; break }
                    }
                }
            }
            // 'required' already computed from facts above; if facts were missing, required stays empty.
            let missing = Array(required.filter { present[$0] == nil }).sorted()
            let body = try? JSONSerialization.data(withJSONObject: ["required": Array(required).sorted(), "missing": missing])
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: body ?? Data())
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = ToolsFactoryOpenAPI(persistence: svc)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        let env = ProcessInfo.processInfo.environment
        let preferred = Int(env["TOOLS_FACTORY_PORT"] ?? env["PORT"] ?? "8011") ?? 8011
        var bound: Int
        do {
            bound = try await server.start(port: preferred)
        } catch {
            // Fallback to an ephemeral port on bind failure (e.g., EADDRINUSE)
            FileHandle.standardError.write(Data("[tools-factory] Port :\(preferred) unavailable (\(error)). Trying ephemeral…\n".utf8))
            bound = try await server.start(port: 0)
        }
        print("tools-factory (NIO) listening on :\(bound)")
        if let pf = env["TOOLS_FACTORY_PORT_FILE"], !pf.isEmpty {
            try? String(bound).data(using: .utf8)?.write(to: URL(fileURLWithPath: pf))
        }
    } catch {
        FileHandle.standardError.write(Data("[tools-factory] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
