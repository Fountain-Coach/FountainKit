import Foundation
import Yams
import FountainStoreClient

@main
struct OpenAPIToFacts {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty {
            fputs("usage: openapi-to-facts <openapi.(yaml|yml|json)> [--agent-id <id>] [--out <file.json>] [--seed]\n", stderr)
            exit(2)
        }
        let path = args.removeFirst()
        var agentId: String? = nil
        var outFile: String? = nil
        var seed = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--agent-id": if i+1 < args.count { agentId = args[i+1]; i += 2 } else { i += 1 }
            case "--out": if i+1 < args.count { outFile = args[i+1]; i += 2 } else { i += 1 }
            case "--seed": seed = true; i += 1
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
            let facts = try makeFacts(openapi: oai)
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

    static func makeFacts(openapi: [String: Any]) throws -> [String: Any] {
        let info = (openapi["info"] as? [String: Any]) ?? [:]
        let title = (info["title"] as? String) ?? "Service"
        let svc = normalizeId(title)
        guard let paths = openapi["paths"] as? [String: Any] else { throw err("openapi.paths missing") }
        let components = (openapi["components"] as? [String: Any]) ?? [:]
        var properties: [[String: Any]] = []
        for (p, v) in paths {
            guard let ops = v as? [String: Any] else { continue }
            let pathLevelParams = ops["parameters"] as? [Any]
            for (method, metaAny) in ops {
                let m = method.lowercased()
                if ["get","put","post","patch","delete"].contains(m) == false { continue }
                guard let meta = metaAny as? [String: Any] else { continue }
                let opId = (meta["operationId"] as? String).map(normalizeId)
                let id = opId ?? makeId(svc: svc, method: m, path: p)
                var entry: [String: Any] = [
                    "id": id,
                    "type": "json",
                    "mapsTo": ["openapi": ["method": m.uppercased(), "path": p]]
                ]
                if let rb = meta["requestBody"] as? [String: Any], let content = rb["content"] as? [String: Any], content.keys.contains("application/json") {
                    var mapsTo = (entry["mapsTo"] as? [String: Any]) ?? [:]
                    var openapiMap = (mapsTo["openapi"] as? [String: Any]) ?? [:]
                    openapiMap["body"] = "json"
                    mapsTo["openapi"] = openapiMap
                    entry["mapsTo"] = mapsTo
                    entry["writable"] = true
                    // Attempt to generate a minimal sample request body
                    if let schemaAny = (content["application/json"] as? [String: Any])?["schema"],
                       let sample = generateSample(from: schemaAny, components: components) {
                        entry["samples"] = ["request": sample]
                    }
                } else if m == "get" { entry["readable"] = true }

                // Enriched descriptor: params (path/query) + request schema shape (flattened)
                var descriptor: [String: Any] = [:]
                // Parameters
                var params: [String: [[String: Any]]] = [:]
                let mergedParams = mergeParams(pathLevelParams, meta["parameters"] as? [Any])
                if !mergedParams.isEmpty {
                    var pathArr: [[String: Any]] = []
                    var queryArr: [[String: Any]] = []
                    for pAny in mergedParams {
                        guard let pObj = pAny as? [String: Any] else { continue }
                        let name = pObj["name"] as? String ?? "param"
                        let loc = (pObj["in"] as? String ?? "query").lowercased()
                        let required = pObj["required"] as? Bool ?? false
                        let t = (pObj["schema"] as? [String: Any])?["type"] as? String ?? "string"
                        let desc: [String: Any] = ["name": name, "type": t, "required": required]
                        if loc == "path" { pathArr.append(desc) } else if loc == "query" { queryArr.append(desc) }
                    }
                    if !pathArr.isEmpty { params["path"] = pathArr }
                    if !queryArr.isEmpty { params["query"] = queryArr }
                }
                if !params.isEmpty { descriptor["params"] = params }
                // Request schema (flattened) when JSON body present
                if let rb = meta["requestBody"] as? [String: Any], let content = rb["content"] as? [String: Any], let app = content["application/json"] as? [String: Any], let schema = app["schema"] {
                    if let flat = flattenSchema(schema, components: components) { descriptor["request"] = ["schema": flat] }
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
        var node: Any = schemaAny
        if let ref = (schemaAny as? [String: Any])?["$ref"] as? String, let target = resolveRef(ref, components: components) { node = target }
        guard let obj = node as? [String: Any] else { return nil }
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
        try await store.putDoc(corpusId: corpus, collection: "agent-facts", id: key, body: facts)
        FileHandle.standardError.write(Data("[openapi-to-facts] seeded facts id=\(key) corpus=\(corpus)\n".utf8))
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
