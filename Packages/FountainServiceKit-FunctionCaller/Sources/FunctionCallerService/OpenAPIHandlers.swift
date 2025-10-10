import Foundation
import OpenAPIRuntime
import AsyncHTTPClient
import FountainStoreClient

public struct FunctionCallerOpenAPI: APIProtocol, @unchecked Sendable {
    let persistence: FountainStoreClient
    let httpClient: HTTPClient

    public init(persistence: FountainStoreClient, httpClient: HTTPClient = HTTPClient(eventLoopGroupProvider: .singleton)) {
        self.persistence = persistence
        self.httpClient = httpClient
    }

    private func toSendable(_ value: Any) -> (any Sendable)? {
        if value is NSNull { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber {
            // NSNumber can represent Bool, Int, Double; preserve types where possible
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            if String(cString: n.objCType) == "d" || String(cString: n.objCType) == "f" { return n.doubleValue }
            return n.intValue
        }
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i }
        if let d = value as? Double { return d }
        if let arr = value as? [Any] {
            return arr.compactMap { toSendable($0) }
        }
        if let dict = value as? [String: Any] {
            var out: [String: (any Sendable)?] = [:]
            for (k, v) in dict { out[k] = toSendable(v) }
            return out
        }
        // Fallback: stringify unknown types
        return String(describing: value)
    }

    // NOTE: HTTPClient is a long-lived dependency; lifecycle managed by process.

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        let body = "function_caller_requests_total 0\n"
        return .ok(.init(body: .plainText(HTTPBody(body))))
    }

    public func list_functions(_ input: Operations.list_functions.Input) async throws -> Operations.list_functions.Output {
        let page = input.query.page ?? 1
        let pageSize = input.query.page_size ?? 20
        let limit = max(min(pageSize, 100), 1)
        let p = max(page, 1)
        let offset = (p - 1) * limit
        let (total, funcs) = try await persistence.listFunctions(limit: limit, offset: offset)
        let items: [Components.Schemas.FunctionInfo] = funcs.map { f in
            let method = Components.Schemas.FunctionInfo.http_methodPayload(rawValue: f.httpMethod.uppercased()) ?? .GET
            return Components.Schemas.FunctionInfo(
                function_id: f.functionId,
                name: f.name,
                description: f.description,
                http_method: method,
                http_path: f.httpPath,
                parameters_schema: nil
            )
        }
        let payload = Operations.list_functions.Output.Ok.Body.jsonPayload(
            functions: items,
            page: p,
            page_size: limit,
            total: total
        )
        return .ok(.init(body: .json(payload)))
    }

    public func get_function_details(_ input: Operations.get_function_details.Input) async throws -> Operations.get_function_details.Output {
        let fid = input.path.function_id
        if let fn = try await persistence.getFunctionDetails(functionId: fid) {
            let method = Components.Schemas.FunctionInfo.http_methodPayload(rawValue: fn.httpMethod.uppercased()) ?? .GET
            let info = Components.Schemas.FunctionInfo(
                function_id: fn.functionId,
                name: fn.name,
                description: fn.description,
                http_method: method,
                http_path: fn.httpPath,
                parameters_schema: nil
            )
            return .ok(.init(body: .json(info)))
        }
        let notFound = Components.Responses.NotFoundResponse(
            body: .json(.init(error_code: "not_found", message: "function \(fid) not found"))
        )
        return .notFound(notFound)
    }

    public func invoke_function(_ input: Operations.invoke_function.Input) async throws -> Operations.invoke_function.Output {
        let fid = input.path.function_id
        guard let fn = try await persistence.getFunctionDetails(functionId: fid) else {
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        }
        var req = HTTPClientRequest(url: fn.httpPath)
        req.method = .RAW(value: fn.httpMethod)
        if case let .json(container) = input.body {
            let dict = container.value
            var anyDict: [String: Any] = [:]
            for (k, v) in dict { anyDict[k] = v ?? NSNull() }
            if let data = try? JSONSerialization.data(withJSONObject: anyDict) {
                req.body = .bytes(data)
                req.headers.add(name: "Content-Type", value: "application/json")
            }
        }
        do {
            let resp = try await httpClient.execute(req, timeout: .seconds(30))
            var bytes = Data()
            for try await buf in resp.body { bytes.append(contentsOf: buf.readableBytesView) }
            if let obj = try? JSONSerialization.jsonObject(with: bytes, options: []) {
                if let dict = obj as? [String: Any] {
                    var sendableDict: [String: (any Sendable)?] = [:]
                    for (k, v) in dict { sendableDict[k] = toSendable(v) }
                    if let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: sendableDict) {
                        return .ok(.init(body: .json(container)))
                    }
                }
            }
            return .undocumented(statusCode: Int(resp.status.code), OpenAPIRuntime.UndocumentedPayload())
        } catch {
            return .undocumented(statusCode: 500, OpenAPIRuntime.UndocumentedPayload())
        }
    }
}
