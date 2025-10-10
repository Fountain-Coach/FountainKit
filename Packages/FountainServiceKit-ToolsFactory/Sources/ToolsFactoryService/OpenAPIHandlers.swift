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
        let body = Operations.list_tools.Output.Ok.Body.jsonPayload(
            functions: items,
            page: p,
            page_size: limit,
            total: total
        )
        return .ok(.init(body: .json(body)))
    }

    public func register_openapi(_ input: Operations.register_openapi.Input) async throws -> Operations.register_openapi.Output {
        // TODO: Parse and register tools from the provided OpenAPI document.
        // For now, return the current list to acknowledge receipt.
        let (_, itemsOut) = try await list_tools(.init(query: .init(page: 1, page_size: 20))).ok
        return .ok(.init(body: itemsOut.body))
    }

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        let body = "tools_factory_up 1\n"
        return .ok(.init(body: .plainText(HTTPBody(body))))
    }
}

