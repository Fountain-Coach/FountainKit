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

    deinit { try? httpClient.syncShutdown() }

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        let body = "function_caller_requests_total 0\n"
        return .ok(.init(body: .text_plain(.init(HTTPBody(body)))))
    }

    public func list_functions(_ input: Operations.list_functions.Input) async throws -> Operations.list_functions.Output {
        let page = input.query.page ?? 1
        let pageSize = input.query.page_size ?? 20
        let limit = max(min(pageSize, 100), 1)
        let p = max(page, 1)
        let offset = (p - 1) * limit
        let (total, funcs) = try await persistence.listFunctions(limit: limit, offset: offset)
        let items: [[String: Any]] = funcs.map { f in
            [
                "function_id": f.functionId,
                "name": f.name,
                "description": f.description,
                "http_method": f.httpMethod,
                "http_path": f.httpPath,
            ]
        }
        let obj: [String: Any] = [
            "functions": items,
            "page": p,
            "page_size": limit,
            "total": total
        ]
        if let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: obj) {
            return .ok(.init(body: .json(container)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func get_function_details(_ input: Operations.get_function_details.Input) async throws -> Operations.get_function_details.Output {
        let fid = input.path.function_id
        if let fn = try await persistence.getFunctionDetails(functionId: fid) {
            let obj: [String: Any] = [
                "function_id": fn.functionId,
                "name": fn.name,
                "description": fn.description,
                "http_method": fn.httpMethod,
                "http_path": fn.httpPath
            ]
            if let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: obj) {
                // Return as undocumented to avoid enum bridging complexity
                return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(container))
            }
            return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
        }
        return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
    }

    public func invoke_function(_ input: Operations.invoke_function.Input) async throws -> Operations.invoke_function.Output {
        let fid = input.path.function_id
        guard let fn = try await persistence.getFunctionDetails(functionId: fid) else {
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        }
        var req = HTTPClientRequest(url: fn.httpPath)
        req.method = .RAW(value: fn.httpMethod)
        if case let .json(container) = input.body {
            if let any = try? container.get(), let data = try? JSONSerialization.data(withJSONObject: any) {
                req.body = .bytes(data)
                req.headers.add(name: "Content-Type", value: "application/json")
            }
        }
        do {
            let resp = try await httpClient.execute(req, timeout: .seconds(30))
            var bytes = Data()
            for try await buf in resp.body { bytes.append(contentsOf: buf.readableBytesView) }
            if let obj = try? JSONSerialization.jsonObject(with: bytes, options: []) {
                if let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: obj) {
                    return .ok(.init(body: .json(container)))
                }
            }
            return .undocumented(statusCode: Int(resp.status.code), OpenAPIRuntime.UndocumentedPayload())
        } catch {
            return .undocumented(statusCode: 500, OpenAPIRuntime.UndocumentedPayload())
        }
    }
}

