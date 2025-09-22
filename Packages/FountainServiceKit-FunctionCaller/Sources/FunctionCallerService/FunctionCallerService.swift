import Foundation
import AsyncHTTPClient
import FountainRuntime
import FountainStoreClient

public struct FunctionInfo: Codable, Sendable {
    public let function_id: String
    public let name: String
    public let description: String
    public let http_method: String
    public let http_path: String
    public let parameters_schema: [String: String]?
    public init(function_id: String, name: String, description: String, http_method: String, http_path: String, parameters_schema: [String: String]? = nil) {
        self.function_id = function_id
        self.name = name
        self.description = description
        self.http_method = http_method
        self.http_path = http_path
        self.parameters_schema = parameters_schema
    }
}

public struct ErrorResponse: Codable, Sendable {
    public let error_code: String
    public let message: String
    public init(error_code: String, message: String) {
        self.error_code = error_code
        self.message = message
    }
}

public struct FunctionsListResponse: Codable, Sendable {
    public let functions: [FunctionInfo]
    public let page: Int
    public let page_size: Int
    public let total: Int
    public init(functions: [FunctionInfo], page: Int, page_size: Int, total: Int) {
        self.functions = functions
        self.page = page
        self.page_size = page_size
        self.total = total
    }
}

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public final class FunctionCallerRouter: @unchecked Sendable {
    let persistence: FountainStoreClient
    let client: HTTPClient

    public init(persistence: FountainStoreClient, client: HTTPClient = HTTPClient(eventLoopGroupProvider: .singleton)) {
        self.persistence = persistence
        self.client = client
    }

    deinit {
        try? client.syncShutdown()
    }

    // MARK: - OpenAPI Handlers

    public func list_functions(page: Int, page_size: Int) async throws -> HTTPResponse {
        let limit = max(min(page_size, 100), 1)
        let p = max(page, 1)
        let offset = (p - 1) * limit
        let (total, funcs) = try await persistence.listFunctions(limit: limit, offset: offset)
        let infos = funcs.map { FunctionInfo(function_id: $0.functionId, name: $0.name, description: $0.description, http_method: $0.httpMethod, http_path: $0.httpPath) }
        let list = FunctionsListResponse(functions: infos, page: p, page_size: limit, total: total)
        let data = try JSONEncoder().encode(list)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func get_function_details(function_id: String) async throws -> HTTPResponse {
        if let fn = try await persistence.getFunctionDetails(functionId: function_id) {
            let info = FunctionInfo(function_id: fn.functionId, name: fn.name, description: fn.description, http_method: fn.httpMethod, http_path: fn.httpPath)
            let data = try JSONEncoder().encode(info)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        }
        let err = ErrorResponse(error_code: "not_found", message: "function not found")
        let data = try JSONEncoder().encode(err)
        return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: data)
    }

    public func invoke_function(function_id: String, body: Data) async throws -> HTTPResponse {
        guard let fn = try await persistence.getFunctionDetails(functionId: function_id) else {
            let err = ErrorResponse(error_code: "not_found", message: "function not found")
            let data = try JSONEncoder().encode(err)
            return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: data)
        }
        var req = HTTPClientRequest(url: fn.httpPath)
        req.method = .RAW(value: fn.httpMethod)
        if !body.isEmpty { req.body = .bytes(body) }
        do {
            let resp = try await client.execute(req, timeout: .seconds(30))
            var headers: [String: String] = [:]
            for (name, value) in resp.headers { headers[name] = value }
            var respBody = Data()
            for try await buffer in resp.body {
                respBody.append(contentsOf: buffer.readableBytesView)
            }
            return HTTPResponse(status: Int(resp.status.code), headers: headers, body: respBody)
        } catch {
            let err = ErrorResponse(error_code: "invoke_error", message: error.localizedDescription)
            let data = try JSONEncoder().encode(err)
            return HTTPResponse(status: 500, headers: ["Content-Type": "application/json"], body: data)
        }
    }

    public func metrics_metrics_get() async -> HTTPResponse {
        let body = Data("function_caller_requests_total 0\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let parts = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = parts.first.map(String.init) ?? request.path
        let query = parts.dropFirst().first.map(String.init) ?? ""
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: true)
        switch request.method {
        case "GET" where segments == ["functions"]:
            let params = Self.parseQuery(query)
            let page = Int(params["page"] ?? "1") ?? 1
            let pageSize = Int(params["page_size"] ?? "20") ?? 20
            return try await list_functions(page: page, page_size: pageSize)
        case "GET" where segments.count == 2 && segments[0] == "functions":
            let fid = String(segments[1])
            return try await get_function_details(function_id: fid)
        case "POST" where segments.count == 3 && segments[0] == "functions" && segments[2] == "invoke":
            let fid = String(segments[1])
            return try await invoke_function(function_id: fid, body: request.body)
        case "GET" where segments == ["metrics"]:
            return await metrics_metrics_get()
        default:
            return HTTPResponse(status: 404)
        }
    }

    static func parseQuery(_ q: String) -> [String: String] {
        var dict: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if kv.count == 2 {
                dict[String(kv[0])] = String(kv[1])
            }
        }
        return dict
    }
}

public func makeFunctionCallerKernel(service svc: FountainStoreClient) -> HTTPKernel {
    let router = FunctionCallerRouter(persistence: svc)
    return HTTPKernel { req in
        let ar = HTTPRequest(method: req.method, path: req.path, headers: req.headers, body: req.body)
        let resp = try await router.route(ar)
        return FountainRuntime.HTTPResponse(status: resp.status, headers: resp.headers, body: resp.body)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
