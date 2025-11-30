import Foundation
import OpenAPIRuntime
import FountainStoreClient

public struct ToolsFactoryOpenAPI: APIProtocol, @unchecked Sendable {
    let persistence: FountainStoreClient

    public init(persistence: FountainStoreClient) { self.persistence = persistence }

    public func list_tools(_ input: Operations.list_tools.Input) async throws -> Operations.list_tools.Output {
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
                parameters_schema: nil,
                openapi: nil
            )
        }
        let payload = Components.Schemas.FunctionListResponse(
            functions: items,
            page: p,
            page_size: limit,
            total: total
        )
        return .ok(.init(body: .json(payload)))
    }

    public func register_openapi(_ input: Operations.register_openapi.Input) async throws -> Operations.register_openapi.Output {
        // Parse OpenAPI and register each operation as a function in the tools catalog.
        guard case let .json(spec) = input.body else {
            let out = try await list_tools(query: .init(page: 1, page_size: 20)).ok
            let payload = try out.body.json
            return .ok(.init(body: .json(payload)))
        }
        // Extract a base URL from servers[] when available to produce absolute paths.
        let data = try JSONEncoder().encode(spec)
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let servers = obj["servers"] as? [[String: Any]] ?? []
        let serverURL: String? = {
            for s in servers {
                if let url = s["url"] as? String, url.lowercased().contains("localhost") { return url }
            }
            return (servers.first?["url"] as? String)
        }()
        func absPath(_ p: String) -> String {
            guard let base = serverURL, p.hasPrefix("/") else { return p }
            let b = base.hasSuffix("/") ? String(base.dropLast()) : base
            return b + p
        }
        let corpus = input.query.corpusId ?? "tools-factory"
        // Ensure corpus exists, so other services (FunctionCaller) enumerate it.
        _ = try? await persistence.createCorpus(corpus)
        let paths = obj["paths"] as? [String: Any] ?? [:]
        var registered: [Components.Schemas.FunctionInfo] = []
        for (path, methodsAny) in paths {
            guard let methods = methodsAny as? [String: Any] else { continue }
            for (methodRaw, opAny) in methods {
                let method = methodRaw.uppercased()
                guard ["GET","POST","PUT","PATCH","DELETE"].contains(method) else { continue }
                guard let op = opAny as? [String: Any] else { continue }
                guard let opId = op["operationId"] as? String else { continue }
                let name = (op["summary"] as? String) ?? opId
                let desc = (op["description"] as? String) ?? ""
                let model = FunctionModel(corpusId: corpus, functionId: opId, name: name, description: desc, httpMethod: method, httpPath: absPath(path))
                _ = try await persistence.addFunction(model)
                let httpMethod = Components.Schemas.FunctionInfo.http_methodPayload(rawValue: method) ?? .GET
                registered.append(.init(function_id: model.functionId, name: model.name, description: model.description, http_method: httpMethod, http_path: model.httpPath, parameters_schema: nil, openapi: nil))
            }
        }
        let payload = Components.Schemas.FunctionListResponse(functions: registered, page: 1, page_size: registered.count, total: registered.count)
        return .ok(.init(body: .json(payload)))
    }

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        let body = "tools_factory_up 1\n"
        return .ok(.init(body: .plainText(HTTPBody(body))))
    }

    // Stub implementations to satisfy generated APIProtocol; real logic lives in tools-factory-server.
    public func agentFacts_fromOpenAPI(_ input: Operations.agentFacts_fromOpenAPI.Input) async throws -> Operations.agentFacts_fromOpenAPI.Output {
        let err = Components.Schemas.ErrorResponse(
            error_code: "not_implemented",
            message: "agentFacts_fromOpenAPI not implemented in ToolsFactoryService stub; run tools-factory-server instead."
        )
        return .internalServerError(.init(body: .json(err)))
    }

    public func agentFacts_get(_ input: Operations.agentFacts_get.Input) async throws -> Operations.agentFacts_get.Output {
        let err = Components.Schemas.ErrorResponse(
            error_code: "not_found",
            message: "agentFacts_get stubbed; facts served by tools-factory-server runtime."
        )
        return .notFound(.init(body: .json(err)))
    }
}
