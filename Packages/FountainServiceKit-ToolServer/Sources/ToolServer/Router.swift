import Foundation
import FountainStoreClient
import Yams

public protocol ToolAdapter {
    var tool: String { get }
    func run(args: [String]) throws -> (Data, Int32)
}

public struct Router {
    let adapters: [String: ToolAdapter]
    let validator = Validation()
    let manifest: ToolManifest
    let persistence: FountainStoreClient?
    let defaultCorpusId: String

    public init(adapters: [String: ToolAdapter], manifest: ToolManifest, persistence: FountainStoreClient? = nil, defaultCorpusId: String = "tools-factory") {
        self.adapters = adapters
        self.manifest = manifest
        self.persistence = persistence
        self.defaultCorpusId = defaultCorpusId
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let pathOnly = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? request.path
        if request.method == "GET" {
            switch pathOnly {
            case "/openapi.yaml":
                let url = URL(fileURLWithPath: "Sources/ToolServer/openapi.yaml")
                let data = try Data(contentsOf: url)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            case "/_health":
                let data = Data("{\"status\":\"ok\"}".utf8)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            case "/metrics":
                let uptime = Int(ProcessInfo.processInfo.systemUptime)
                let body = Data("uptime_seconds \(uptime)\n".utf8)
                return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
            case "/manifest":
                let data = try JSONEncoder().encode(manifest)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            default:
                // /tools with pagination
                if pathOnly == "/tools" { return try await listTools(request) }
                break
            }
        }

        guard request.method == "POST" else { return HTTPResponse(status: 405) }
        if pathOnly == "/tools/register" {
            return try await registerTools(request)
        }
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count == 2, let adapter = adapters[parts[1]] else { return HTTPResponse(status: 404) }

        let payload = try JSONDecoder().decode(ToolRequest.self, from: request.body)
        try validator.validate(args: payload.args)
        let result = try adapter.run(args: payload.args)
        return HTTPResponse(status: Int(result.1 == 0 ? 200 : 500), body: result.0)
    }

    // MARK: Tools Factory API
    private func parseQuery(_ path: String) -> [String: String] {
        guard let qIndex = path.firstIndex(of: "?") else { return [:] }
        let query = path[path.index(after: qIndex)...]
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }

    private func listTools(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let svc = persistence else {
            let err = ["error_code": "persistence_unavailable", "message": "FountainStore not configured"]
            let data = try JSONSerialization.data(withJSONObject: err)
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: data)
        }
        let qp = parseQuery(request.path)
        let page = max(Int(qp["page"] ?? "1") ?? 1, 1)
        let pageSize = min(max(Int(qp["page_size"] ?? "20") ?? 20, 1), 100)
        let offset = (page - 1) * pageSize
        let (total, functions) = try await svc.listFunctions(corpusId: defaultCorpusId, limit: pageSize, offset: offset)
        let items: [[String: Any]] = functions.map { f in
            [
                "function_id": f.functionId,
                "name": f.name,
                "description": f.description,
                "http_method": f.httpMethod,
                "http_path": f.httpPath
            ]
        }
        let resp: [String: Any] = [
            "functions": items,
            "page": page,
            "page_size": pageSize,
            "total": total
        ]
        let data = try JSONSerialization.data(withJSONObject: resp)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private func registerTools(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let svc = persistence else {
            let err = ["error_code": "persistence_unavailable", "message": "FountainStore not configured"]
            let data = try JSONSerialization.data(withJSONObject: err)
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: data)
        }
        // Parse corpusId from query, default to configured corpus
        let qp = parseQuery(request.path)
        let corpus = qp["corpusId"] ?? defaultCorpusId
        // Optional: resolve base URL from query override or servers[0].url
        let baseOverride = qp["base"]

        // Decode OpenAPI (JSON first; fallback to YAML)
        let obj: [String: Any]
        if let jsonObj = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
            obj = jsonObj
        } else if let text = String(data: request.body, encoding: .utf8),
                  let yamlObj = try? Yams.load(yaml: text) as? [String: Any] {
            obj = yamlObj
        } else {
            let err = ["error_code": "invalid_openapi", "message": "Body must be OpenAPI JSON or YAML"]
            let data = try JSONSerialization.data(withJSONObject: err)
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: data)
        }

        // Resolve base URL
        var baseURL: String? = baseOverride
        if baseURL == nil, let servers = obj["servers"] as? [[String: Any]],
           let first = servers.first, let urlStr = first["url"] as? String, !urlStr.isEmpty {
            baseURL = urlStr
        }

        let pathMap = obj["paths"] as? [String: Any] ?? [:]
        var registered: [[String: Any]] = []
        for (path, methodsAny) in pathMap {
            guard let methods = methodsAny as? [String: Any] else { continue }
            for (methodRaw, opAny) in methods {
                let method = methodRaw.uppercased()
                guard ["GET","POST","PUT","PATCH","DELETE"].contains(method) else { continue }
                guard let op = opAny as? [String: Any] else { continue }
                guard let opId = op["operationId"] as? String else { continue }
                let name = (op["summary"] as? String) ?? opId
                let desc = (op["description"] as? String) ?? ""
                // Build absolute httpPath when possible
                let httpPath: String
                if path.hasPrefix("http://") || path.hasPrefix("https://") {
                    httpPath = path
                } else if let base = baseURL, !base.isEmpty {
                    if base.hasSuffix("/") && path.hasPrefix("/") {
                        httpPath = base + String(path.dropFirst())
                    } else if !base.hasSuffix("/") && !path.hasPrefix("/") {
                        httpPath = base + "/" + path
                    } else {
                        httpPath = base + path
                    }
                } else {
                    httpPath = path
                }
                let f = FunctionModel(corpusId: corpus, functionId: opId, name: name, description: desc, httpMethod: method, httpPath: httpPath)
                _ = try await svc.addFunction(f)
                registered.append([
                    "function_id": f.functionId,
                    "name": f.name,
                    "description": f.description,
                    "http_method": f.httpMethod,
                    "http_path": f.httpPath
                ])
            }
        }
        let resp: [String: Any] = [
            "functions": registered,
            "page": 1,
            "page_size": registered.count,
            "total": registered.count
        ]
        let data = try JSONSerialization.data(withJSONObject: resp)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }
}

public struct ToolRequest: Codable {
    public let args: [String]
    public let request_id: String?
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
