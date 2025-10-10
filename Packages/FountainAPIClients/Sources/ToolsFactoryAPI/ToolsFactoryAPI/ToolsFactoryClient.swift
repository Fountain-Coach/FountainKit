import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// High-level wrapper around the generated Tools Factory API client.
public struct ToolsFactoryClient: Sendable {

    /// Errors produced by ``ToolsFactoryClient`` when responses cannot be mapped.
    public enum ToolsFactoryClientError: Error, Sendable, Equatable {
        /// The service returned a status code that is not explicitly modelled.
        case unexpectedStatus(code: Int)
        /// The service reported a validation error (HTTP 422).
        case validationError(Components.Schemas.ErrorResponse)
        /// The expected response body was missing or encoded using an unsupported format.
        case missingResponseBody(operation: String)
        /// Metrics responses could not be decoded as UTF-8 text.
        case invalidPlainTextEncoding(operation: String)
    }

    /// Alias representing the paginated function list payload.
    public typealias FunctionListResponse = Components.Schemas.FunctionListResponse

    /// Alias representing the OpenAPI document accepted by the register endpoint.
    public typealias OpenAPIDocument = Operations.register_openapi.Input.Body.jsonPayload

    private let client: Client

    /// Creates a client backed by ``URLSession``.
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: defaultHeaders)
        self.client = Client(serverURL: baseURL, transport: transport, middlewares: middlewares)
    }

    /// Creates a client backed by ``AsyncHTTPClient``.
    public init(
        baseURL: URL,
        httpClient: HTTPClient,
        defaultHeaders: [String: String] = [:],
        timeout: TimeAmount? = nil,
        requestBodyMaxBytes: Int = AsyncHTTPClientTransport.Configuration.defaultRequestBodyMaxBytes,
        responseBodyMaxBytes: Int = AsyncHTTPClientTransport.Configuration.defaultResponseBodyMaxBytes
    ) {
        let transport = AsyncHTTPClientTransport(
            client: httpClient,
            timeout: timeout,
            requestBodyMaxBytes: requestBodyMaxBytes,
            responseBodyMaxBytes: responseBodyMaxBytes
        )
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: defaultHeaders)
        self.client = Client(serverURL: baseURL, transport: transport, middlewares: middlewares)
    }

    /// Lists registered tools with optional pagination.
    public func listTools(page: Int? = nil, pageSize: Int? = nil) async throws -> FunctionListResponse {
        let query = Operations.list_tools.Input.Query(
            page: page.map(Int32.init),
            page_size: pageSize.map(Int32.init)
        )
        let output = try await client.list_tools(.init(query: query))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw ToolsFactoryClientError.missingResponseBody(operation: "list_tools")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw ToolsFactoryClientError.validationError(error)
            }
            throw ToolsFactoryClientError.missingResponseBody(operation: "list_tools")
        case .undocumented(let status, _):
            throw ToolsFactoryClientError.unexpectedStatus(code: status)
        }
    }

    /// Registers tools defined by the supplied OpenAPI document.
    public func registerTools(
        corpusID: String? = nil,
        document: OpenAPIDocument
    ) async throws -> FunctionListResponse {
        let query = Operations.register_openapi.Input.Query(
            corpusId: corpusID
        )
        let output = try await client.register_openapi(
            .init(query: query, body: .json(document))
        )
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw ToolsFactoryClientError.missingResponseBody(operation: "register_openapi")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw ToolsFactoryClientError.validationError(error)
            }
            throw ToolsFactoryClientError.missingResponseBody(operation: "register_openapi")
        case .undocumented(let status, _):
            throw ToolsFactoryClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches Prometheus metrics exposed by the Tools Factory service.
    public func metrics() async throws -> String {
        let output = try await client.metrics_metrics_get(.init())
        switch output {
        case .ok(let ok):
            guard case let .plainText(body) = ok.body else {
                throw ToolsFactoryClientError.missingResponseBody(operation: "metrics")
            }
            let data = try await Data(collecting: body, upTo: 1 * 1_048_576)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ToolsFactoryClientError.invalidPlainTextEncoding(operation: "metrics")
            }
            return text
        case .undocumented(let status, _):
            throw ToolsFactoryClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
