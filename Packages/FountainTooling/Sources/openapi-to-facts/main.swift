import Foundation
import Yams
import FountainStoreClient

@main
struct OpenAPIToFacts {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty {
            fputs("usage: openapi-to-facts <openapi.(yaml|yml|json)> [--agent-id <id>] [--out <file.json>] [--seed] [--allow-tools-only]\n", stderr)
            exit(2)
        }
        let path = args.removeFirst()
        var agentId: String? = nil
        var outFile: String? = nil
        var seed = false
        var allowToolsOnly = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--agent-id": if i+1 < args.count { agentId = args[i+1]; i += 2 } else { i += 1 }
            case "--out": if i+1 < args.count { outFile = args[i+1]; i += 2 } else { i += 1 }
            case "--seed": seed = true; i += 1
            case "--allow-tools-only": allowToolsOnly = true; i += 1
            default: i += 1
            }
        }
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let obj: Any
            if path.hasSuffix(".yaml") || path.hasSuffix(".yml") {
                obj = try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as Any
            } else { obj = try JSONSerialization.jsonObject(with: data) }
            guard let oai = obj as? [String: Any] else { throw err("openapi is not an object") }
            let facts = try makeFacts(openapi: oai, allowToolsOnly: allowToolsOnly)
            let json = try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted])
            if let out = outFile {
                try json.write(to: URL(fileURLWithPath: out))
            } else {
                FileHandle.standardOutput.write(json)
            }
            if seed {
                try await seedFacts(agentId: agentId, facts: json)
            }
        } catch {
            fputs("openapi-to-facts error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func makeFacts(openapi: [String: Any], allowToolsOnly: Bool = false) throws -> [String: Any] {
        let info = (openapi["info"] as? [String: Any]) ?? [:]
        let title = (info["title"] as? String) ?? "Service"
        let svc = normalizeId(title)
        guard let paths = openapi["paths"] as? [String: Any] else { throw err("openapi.paths missing") }
        let components = (openapi["components"] as? [String: Any]) ?? [:]
        // Server hint: prefer operation-level servers, else root servers
        var defaultServerURL: String? = nil
        if let servers = openapi["servers"] as? [[String: Any]], let first = servers.first, let url = first["url"] as? String { defaultServerURL = url }
        var properties: [[String: Any]] = []
        for (p, v) in paths {
            guard let ops = v as? [String: Any] else { continue }
            let pathLevelParams = ops["parameters"] as? [Any]
            for (method, metaAny) in ops {
                let m = method.lowercased()
                if ["get","put","post","patch","delete"].contains(m) == false { continue }
                guard let meta = metaAny as? [String: Any] else { continue }
                if allowToolsOnly && isAllowedAsTool(meta) == false { continue }
                let opId = (meta["operationId"] as? String).map(normalizeId)
                let id = opId ?? makeId(svc: svc, method: m, path: p)
                var entry: [String: Any] = [
                    "id": id,
                    "type": "json",
                    "mapsTo": ["openapi": ["method": m.uppercased(), "path": p]]
                ]
                // Request body classification
                if let rb = meta["requestBody"] as? [String: Any], let content = rb["content"] as? [String: Any] {
                    // JSON
                    if let app = content["application/json"] as? [String: Any] {
                        var mapsTo = (entry["mapsTo"] as? [String: Any]) ?? [:]
                        var openapiMap = (mapsTo["openapi"] as? [String: Any]) ?? [:]
                        openapiMap["body"] = "json"
                        mapsTo["openapi"] = openapiMap
                        entry["mapsTo"] = mapsTo
                        entry["writable"] = true
                        if let schemaAny = app["schema"], let sample = generateSample(from: schemaAny, components: components) {
                            entry["samples"] = ["request": sample]
                        }
                        // Also include a flattened request schema descriptor
                        if let schemaAny = app["schema"], let flat = flattenSchema(schemaAny, components: components) {
                            var descriptor = (entry["descriptor"] as? [String: Any]) ?? [:]
                            descriptor["request"] = ["schema": flat]
                            entry["descriptor"] = descriptor
                        }
                    }
                    // Text
                    else if let txt = content["text/plain"] as? [String: Any] {
                        var mapsTo = (entry["mapsTo"] as? [String: Any]) ?? [:]
                        var openapiMap = (mapsTo["openapi"] as? [String: Any]) ?? [:]
                        openapiMap["body"] = "text"
                        mapsTo["openapi"] = openapiMap
                        entry["mapsTo"] = mapsTo
                        entry["writable"] = true
                        // Minimal sample (string)
                        entry["samples"] = ["request": sampleString(for: nil)]
                        // Descriptor hint
                        var descriptor = (entry["descriptor"] as? [String: Any]) ?? [:]
                        descriptor["request"] = ["type": "text", "contentType": "text/plain"]
                        entry["descriptor"] = descriptor
                        _ = txt // reserved for future schema (OpenAPI 3.1 string schema)
                    }
                    // Binary (raw octet-stream)
                    else if content.keys.contains("application/octet-stream") {
                        var mapsTo = (entry["mapsTo"] as? [String: Any]) ?? [:]
                        var openapiMap = (mapsTo["openapi"] as? [String: Any]) ?? [:]
                        openapiMap["body"] = "binary"
                        mapsTo["openapi"] = openapiMap
                        entry["mapsTo"] = mapsTo
                        entry["writable"] = true
                        var descriptor = (entry["descriptor"] as? [String: Any]) ?? [:]
                        descriptor["request"] = ["type": "binary", "contentType": "application/octet-stream"]
                        entry["descriptor"] = descriptor
                    }
                    // Multipart (form-data)
                    else if let mp = content["multipart/form-data"] as? [String: Any] {
                        var mapsTo = (entry["mapsTo"] as? [String: Any]) ?? [:]
                        var openapiMap = (mapsTo["openapi"] as? [String: Any]) ?? [:]
                        openapiMap["body"] = "multipart"
                        mapsTo["openapi"] = openapiMap
                        entry["mapsTo"] = mapsTo
                        entry["writable"] = true
                        var descriptor = (entry["descriptor"] as? [String: Any]) ?? [:]
                        var req: [String: Any] = ["type": "multipart"]
                        var partsOut: [String: Any] = [:]
                        let schema = mp["schema"]
                        let encoding = (mp["encoding"] as? [String: Any]) ?? [:]
                        var required: [String] = []
                        var props: [String: Any] = [:]
                        // Extract required/props if object schema
                        if let s = schema as? [String: Any] {
                            required = (s["required"] as? [String]) ?? []
                            props = (s["properties"] as? [String: Any]) ?? [:]
                        }
                        for (name, vAny) in props {
                            var pDesc: [String: Any] = [:]
                            // Determine type from property schema (string/binary) and encoding hints
                            var t = (vAny as? [String: Any])?["type"] as? String ?? "string"
                            let fmt = (vAny as? [String: Any])?["format"] as? String
                            if t == "string", fmt == "binary" { t = "binary" }
                            if t == "string" && fmt == nil { t = "string" }
                            pDesc["type"] = (t == "binary") ? "binary" : "string"
                            pDesc["required"] = required.contains(name)
                            if let enc = encoding[name] as? [String: Any], let ct = enc["contentType"] as? String { pDesc["contentType"] = ct }
                            partsOut[name] = pDesc
                        }
                        if !partsOut.isEmpty { req["parts"] = partsOut }
                        descriptor["request"] = req
                        entry["descriptor"] = descriptor
                    }
                } else if m == "get" { entry["readable"] = true }

                // Enriched descriptor: server, security, params (path/query/header/cookie), request/response shapes
                var descriptor: [String: Any] = (entry["descriptor"] as? [String: Any]) ?? [:]
                // Server hint
                if descriptor["serverURL"] == nil {
                    var serverURL: String? = nil
                    if let opServers = meta["servers"] as? [[String: Any]], let first = opServers.first, let url = first["url"] as? String { serverURL = url }
                    if serverURL == nil { serverURL = defaultServerURL }
                    if let s = serverURL { descriptor["serverURL"] = s }
                }
                // Security (minimal): collect header apiKey names from operation or root
                func extractSecurity(_ root: [String: Any]) -> [[String: Any]] {
                    var out: [[String: Any]] = []
                    if let arr = root["security"] as? [[String: Any]] {
                        for req in arr {
                            for (schemeName, _) in req {
                                if let schemes = components["securitySchemes"] as? [String: Any], let s = schemes[schemeName] as? [String: Any] {
                                    let type = (s["type"] as? String) ?? ""
                                    if type == "apiKey", let inLoc = s["in"] as? String, inLoc == "header", let name = s["name"] as? String {
                                        out.append(["type": "apiKey", "in": "header", "name": name, "scheme": schemeName])
                                    } else if type == "http" {
                                        let scheme = (s["scheme"] as? String) ?? ""
                                        out.append(["type": "http", "scheme": scheme, "schemeName": schemeName])
                                    }
                                }
                            }
                        }
                    }
                    return out
                }
                var sec = extractSecurity(meta)
                if sec.isEmpty { sec = extractSecurity(openapi) }
                if !sec.isEmpty { descriptor["security"] = sec }
                // Parameters
                var params: [String: [[String: Any]]] = [:]
                let mergedParams = mergeParams(pathLevelParams, meta["parameters"] as? [Any])
                if !mergedParams.isEmpty {
                    var pathArr: [[String: Any]] = []
                    var queryArr: [[String: Any]] = []
                    var headerArr: [[String: Any]] = []
                    var cookieArr: [[String: Any]] = []
                    for pAny in mergedParams {
                        guard let pObj = pAny as? [String: Any] else { continue }
                        let name = pObj["name"] as? String ?? "param"
                        let loc = (pObj["in"] as? String ?? "query").lowercased()
                        let required = pObj["required"] as? Bool ?? false
                        let t = (pObj["schema"] as? [String: Any])?["type"] as? String ?? "string"
                        let desc: [String: Any] = ["name": name, "type": t, "required": required]
                        switch loc {
                        case "path": pathArr.append(desc)
                        case "query": queryArr.append(desc)
                        case "header": headerArr.append(desc)
                        case "cookie": cookieArr.append(desc)
                        default: break
                        }
                    }
                    if !pathArr.isEmpty { params["path"] = pathArr }
                    if !queryArr.isEmpty { params["query"] = queryArr }
                    if !headerArr.isEmpty { params["header"] = headerArr }
                    if !cookieArr.isEmpty { params["cookie"] = cookieArr }
                }
                if !params.isEmpty { descriptor["params"] = params }
                // Request schema (flattened) when JSON body present
                if let rb = meta["requestBody"] as? [String: Any], let content = rb["content"] as? [String: Any], let app = content["application/json"] as? [String: Any], let schema = app["schema"] {
                    if descriptor["request"] == nil, let flat = flattenSchema(schema, components: components) { descriptor["request"] = ["schema": flat] }
                }
                // Request content types hint
                if let rb = meta["requestBody"] as? [String: Any], let content = rb["content"] as? [String: Any], !content.isEmpty {
                    var req = (descriptor["request"] as? [String: Any]) ?? [:]
                    req["contentTypes"] = Array(content.keys)
                    descriptor["request"] = req
                }
                // Convenience: derive authHeaders from security schemes
                if let secArr = descriptor["security"] as? [[String: Any]] {
                    var headers: Set<String> = []
                    var examples: [String] = []
                    for s in secArr {
                        if (s["type"] as? String) == "apiKey", (s["in"] as? String) == "header", let name = s["name"] as? String { headers.insert(name) }
                        if (s["type"] as? String) == "http" {
                            let scheme = (s["scheme"] as? String)?.lowercased()
                            if scheme == "basic" || scheme == "bearer" { headers.insert("Authorization") }
                            if scheme == "bearer" { examples.append("Authorization: Bearer ${TOKEN}") }
                            if scheme == "basic" { examples.append("Authorization: Basic ${BASE64_USER_PASS}") }
                        }
                    }
                    if !headers.isEmpty { descriptor["authHeaders"] = Array(headers) }
                    // Provide simple header examples for LLMs/tooling UIs
                    // If apiKey header(s) present, include generic example
                    for h in headers where h.lowercased() != "authorization" {
                        examples.append("\(h): ${API_KEY}")
                    }
                    if !examples.isEmpty { descriptor["authHeaderExamples"] = examples }
                }
                // Response descriptor/sample: prefer first 2xx or 200/201, else default; support multiple content types hints
                if let responses = meta["responses"] as? [String: Any] {
                    func pickFirst2xx(_ dict: [String: Any]) -> (String, [String: Any])? {
                        let preferred = ["200","201","202","204"]
                        for k in preferred { if let v = dict[k] as? [String: Any] { return (k, v) } }
                        // any 2xx
                        if let kv = dict.first(where: { $0.key.first == "2" && $0.value is [String: Any] }) {
                            return (kv.key, kv.value as! [String: Any])
                        }
                        if let def = dict["default"] as? [String: Any] { return ("default", def) }
                        return nil
                    }
                    if let (_, resp) = pickFirst2xx(responses) {
                        if let content = resp["content"] as? [String: Any] {
                            let allTypes = Array(content.keys)
                            // JSON
                            if let app = content["application/json"] as? [String: Any] {
                                if let schemaAny = app["schema"], let flat = flattenSchema(schemaAny, components: components) {
                                    var rd: [String: Any] = ["schema": flat]
                                    rd["contentType"] = "application/json"
                                    rd["contentTypes"] = allTypes
                                    descriptor["response"] = rd
                                } else {
                                    var rd: [String: Any] = [:]
                                    rd["contentType"] = "application/json"
                                    rd["contentTypes"] = allTypes
                                    descriptor["response"] = rd
                                }
                                if let schemaAny = app["schema"], let sample = generateSample(from: schemaAny, components: components) {
                                    var samples = (entry["samples"] as? [String: Any]) ?? [:]
                                    samples["response"] = sample
                                    entry["samples"] = samples
                                }
                            }
                            // Text
                            else if content.keys.contains("text/plain") {
                                let rd: [String: Any] = ["type": "text", "contentType": "text/plain", "contentTypes": allTypes]
                                descriptor["response"] = rd
                            }
                            // Binary
                            else if content.keys.contains("application/octet-stream") {
                                let rd: [String: Any] = ["type": "binary", "contentType": "application/octet-stream", "contentTypes": allTypes]
                                descriptor["response"] = rd
                            }
                            // Multipart (pick any multipart/*)
                            else if let mp = content.first(where: { $0.key.lowercased().hasPrefix("multipart/") }) {
                                let rd: [String: Any] = ["type": "multipart", "contentType": mp.key, "contentTypes": allTypes]
                                descriptor["response"] = rd
                            }
                        }
                        // Optional: response headers
                        if let headers = resp["headers"] as? [String: Any] {
                            var hdrs: [[String: Any]] = []
                            for (name, valAny) in headers {
                                if let val = valAny as? [String: Any] {
                                    let t = (val["schema"] as? [String: Any])?["type"] as? String ?? "string"
                                    hdrs.append(["name": name, "type": t])
                                }
                            }
                            if !hdrs.isEmpty {
                                var rd = (descriptor["response"] as? [String: Any]) ?? [:]
                                rd["headers"] = hdrs
                                descriptor["response"] = rd
                            }
                        }
                    }
                }
                if !descriptor.isEmpty { entry["descriptor"] = descriptor }
                properties.append(entry)
            }
        }
        let facts: [String: Any] = [
            "protocol": "midi-ci-pe",
            "functionBlocks": [[
                "name": title,
                "group": 0,
                "properties": properties
            ]]
        ]
        return facts
    }

    static func isAllowedAsTool(_ meta: [String: Any]) -> Bool {
        if let b = meta["x-fountain.allow-as-tool"] as? Bool { return b }
        if let s = meta["x-fountain.allow-as-tool"] as? String { return s.lowercased() == "true" }
        return false
    }

    static func mergeParams(_ a: [Any]?, _ b: [Any]?) -> [Any] {
        var out: [Any] = []
        if let a { out.append(contentsOf: a) }
        if let b { out.append(contentsOf: b) }
        return out
    }

    // MARK: - Sample generation
    // Resolve $ref and synthesize a tiny JSON sample for required fields
    static func generateSample(from schemaAny: Any, components: [String: Any]) -> Any? {
        if let ref = (schemaAny as? [String: Any])?["$ref"] as? String {
            if let target = resolveRef(ref, components: components) {
                return generateSample(from: target, components: components)
            }
        }
        guard let schema = schemaAny as? [String: Any] else { return nil }
        if let type = schema["type"] as? String {
            switch type {
            case "object":
                let required = (schema["required"] as? [String]) ?? []
                let props = (schema["properties"] as? [String: Any]) ?? [:]
                var obj: [String: Any] = [:]
                for key in required {
                    let propSchema = props[key] ?? [:]
                    obj[key] = sampleValue(for: key, schemaAny: propSchema, components: components)
                }
                return obj
            case "array":
                if let items = schema["items"] { return [generateSample(from: items, components: components) ?? [:]] }
                return []
            case "string":
                return sampleString(for: nil)
            case "integer":
                return 0
            case "number":
                return 0
            case "boolean":
                return true
            default:
                return nil
            }
        }
        // allOf/oneOf: pick first
        if let allOf = schema["allOf"] as? [Any], let first = allOf.first {
            return generateSample(from: first, components: components)
        }
        if let oneOf = schema["oneOf"] as? [Any], let first = oneOf.first {
            return generateSample(from: first, components: components)
        }
        return nil
    }

    static func resolveRef(_ ref: String, components: [String: Any]) -> Any? {
        // Expect format '#/components/schemas/TypeName'
        guard ref.hasPrefix("#/components/") else { return nil }
        let parts = ref.split(separator: "/").dropFirst(1) // components/.../...
        var cur: Any? = components
        for part in parts.dropFirst() { // skip leading 'components'
            if let dict = cur as? [String: Any] { cur = dict[String(part)] } else { return nil }
        }
        return cur
    }

    // Flatten a JSON schema to a minimal descriptor: type + required + properties types (1 level)
    static func flattenSchema(_ schemaAny: Any, components: [String: Any]) -> [String: Any]? {
        // Resolve $ref
        var node: Any = schemaAny
        if let ref = (schemaAny as? [String: Any])?["$ref"] as? String, let target = resolveRef(ref, components: components) { node = target }
        guard var obj = node as? [String: Any] else { return nil }
        // Handle oneOf/anyOf/allOf (naive): prefer first entry; for allOf, merge shallow `properties`/`required`
        if let one = obj["oneOf"] as? [Any], let first = one.first { return flattenSchema(first, components: components) }
        if let any = obj["anyOf"] as? [Any], let first = any.first { return flattenSchema(first, components: components) }
        if let all = obj["allOf"] as? [Any] {
            var merged: [String: Any] = [:]
            var reqs: Set<String> = []
            for part in all {
                if let flat = flattenSchema(part, components: components) {
                    if let p = flat["properties"] as? [String: Any] { merged.merge(p, uniquingKeysWith: { a, _ in a }) }
                    if let r = flat["required"] as? [String] { reqs.formUnion(r) }
                }
            }
            var out: [String: Any] = ["type": obj["type"] as? String ?? "object"]
            if !merged.isEmpty { out["properties"] = merged }
            if !reqs.isEmpty { out["required"] = Array(reqs) }
            return out
        }
        var result: [String: Any] = [:]
        if let t = obj["type"] as? String { result["type"] = t }
        if let req = obj["required"] as? [String] { result["required"] = req }
        if let props = obj["properties"] as? [String: Any] {
            var flatProps: [String: Any] = [:]
            for (k, vAny) in props {
                var vNode: Any = vAny
                if let r = (vAny as? [String: Any])?["$ref"] as? String, let t = resolveRef(r, components: components) { vNode = t }
                if let v = vNode as? [String: Any] {
                    var t = v["type"] as? String ?? "object"
                    if t == "array", let items = v["items"] as? [String: Any] {
                        let it = items["type"] as? String ?? "object"
                        t = "array<\(it)>"
                    }
                    flatProps[k] = ["type": t]
                }
            }
            if !flatProps.isEmpty { result["properties"] = flatProps }
        }
        return result
    }

    static func sampleValue(for key: String, schemaAny: Any, components: [String: Any]) -> Any {
        if let ref = (schemaAny as? [String: Any])?["$ref"] as? String, let target = resolveRef(ref, components: components) {
            return generateSample(from: target, components: components) ?? [:]
        }
        guard let schema = schemaAny as? [String: Any] else {
            return sampleString(for: key)
        }
        if let en = schema["enum"] as? [Any], let first = en.first { return first }
        if let type = schema["type"] as? String {
            switch type {
            case "string": return sampleString(for: key)
            case "integer": return 0
            case "number": return 0
            case "boolean": return true
            case "object": return generateSample(from: schema, components: components) ?? [:]
            case "array":
                if let items = schema["items"] { return [generateSample(from: items, components: components) ?? [:]] }
                return []
            default: return sampleString(for: key)
            }
        }
        return sampleString(for: key)
    }

    static func sampleString(for key: String?) -> String {
        switch key ?? "" {
        case "corpusId": return "parity-ci"
        case "baselineId": return "baseline-1"
        case "patternsId": return "patterns-1"
        case "driftId": return "drift-1"
        case "reflectionId": return "refl-1"
        case "question": return "What changed?"
        case "content": return "Lorem ipsum"
        default: return key ?? "sample"
        }
    }

    static func seedFacts(agentId: String?, facts: Data) async throws {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["CORPUS_ID"] ?? "agents"
        guard let agent = agentId ?? env["AGENT_ID"] else { throw err("missing agent id for seeding") }
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        let safeId = agent.replacingOccurrences(of: "/", with: "|")
        let key = "facts:agent:\(safeId)"
        // Merge with existing facts when present so multiple specs can contribute
        // to the same agent (e.g., composer-studio aggregating score/script/cues).
        if let existing = try? await store.getDoc(corpusId: corpus, collection: "agent-facts", id: key),
           let existingObj = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
           let newObj = try? JSONSerialization.jsonObject(with: facts) as? [String: Any] {
            var merged = existingObj
            let existingBlocks = (existingObj["functionBlocks"] as? [[String: Any]]) ?? []
            let newBlocks = (newObj["functionBlocks"] as? [[String: Any]]) ?? []
            merged["protocol"] = existingObj["protocol"] ?? newObj["protocol"] ?? "midi-ci-pe"
            merged["functionBlocks"] = existingBlocks + newBlocks
            let mergedData = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted])
            try await store.putDoc(corpusId: corpus, collection: "agent-facts", id: key, body: mergedData)
            FileHandle.standardError.write(Data("[openapi-to-facts] merged facts id=\(key) corpus=\(corpus) blocks=\(existingBlocks.count)+\(newBlocks.count)\n".utf8))
        } else {
            try await store.putDoc(corpusId: corpus, collection: "agent-facts", id: key, body: facts)
            FileHandle.standardError.write(Data("[openapi-to-facts] seeded facts id=\(key) corpus=\(corpus)\n".utf8))
        }
    }

    static func normalizeId(_ s: String) -> String {
        let lowered = s.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
    static func makeId(svc: String, method: String, path: String) -> String {
        let parts = path.split(separator: "/").map { seg -> String in
            if seg.hasPrefix("{") && seg.hasSuffix("}") { return String(seg.dropFirst().dropLast()) }
            return String(seg)
        }
        let p = parts.joined(separator: ".")
        return normalizeId("\(method).\(p)")
    }
    static func err(_ msg: String) -> NSError { NSError(domain: "openapi-to-facts", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]) }
}
