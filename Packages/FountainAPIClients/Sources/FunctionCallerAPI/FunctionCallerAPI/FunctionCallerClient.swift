import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// High-level convenience wrapper around the generated Function Caller API client.
///
/// The wrapper exposes async methods that return strongly typed models while supporting
/// both URLSession and AsyncHTTPClient transports.
public struct FunctionCallerClient: Sendable {

    /// Errors surfaced by ``FunctionCallerClient`` when responses cannot be represented.
    public enum FunctionCallerClientError: Error, Sendable, Equatable {
        /// The server returned a status code that is not explicitly modelled by the spec.
        case unexpectedStatus(code: Int)
        /// The server reported a validation error (HTTP 422).
        case validationError(Components.Schemas.ErrorResponse)
        /// The requested resource was not found (HTTP 404).
        case notFound(Components.Schemas.ErrorResponse)
        /// The server reported a bad request (HTTP 400).
        case badRequest(Components.Schemas.ErrorResponse)
        /// The expected response body was not present or used an unsupported format.
        case missingResponseBody(operation: String)
        /// Text responses could not be decoded using UTF-8.
        case invalidPlainTextEncoding(operation: String)
    }

    /// Alias describing the paginated function list payload.
    public typealias FunctionListResponse = Operations.list_functions.Output.Ok.Body.jsonPayload

    /// Alias describing the dynamic invocation response payload.
    public typealias InvocationResult = Operations.invoke_function.Output.Ok.Body.jsonPayload

    /// Alias describing the dynamic invocation request payload.
    public typealias InvocationRequestBody = Operations.invoke_function.Input.Body.jsonPayload

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

    /// Creates a client backed by ``AsyncHTTPClient`` for Linux and server deployments.
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

    /// Lists registered functions exposed by the Function Caller service.
    /// - Parameters:
    ///   - page: Optional page index (1-based).
    ///   - pageSize: Optional page size (defaults to 20 server-side).
    /// - Returns: Paginated response payload defined by the OpenAPI spec.
    public func listFunctions(page: Int? = nil, pageSize: Int? = nil) async throws -> FunctionListResponse {
        let query = Operations.list_functions.Input.Query(
            page: page.map(Int32.init),
            page_size: pageSize.map(Int32.init)
        )
        let output = try await client.list_functions(.init(query: query))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FunctionCallerClientError.missingResponseBody(operation: "list_functions")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw FunctionCallerClientError.validationError(error)
            }
            throw FunctionCallerClientError.missingResponseBody(operation: "list_functions")
        case .undocumented(let status, _):
            throw FunctionCallerClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches metadata for the specified function identifier.
    public func getFunctionDetails(functionID: String) async throws -> Components.Schemas.FunctionInfo {
        let output = try await client.get_function_details(.init(path: .init(function_id: functionID)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FunctionCallerClientError.missingResponseBody(operation: "get_function_details")
            }
            return body
        case .notFound(let notFound):
            if case let .json(error) = notFound.body {
                throw FunctionCallerClientError.notFound(error)
            }
            throw FunctionCallerClientError.missingResponseBody(operation: "get_function_details")
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw FunctionCallerClientError.validationError(error)
            }
            throw FunctionCallerClientError.missingResponseBody(operation: "get_function_details")
        case .undocumented(let status, _):
            throw FunctionCallerClientError.unexpectedStatus(code: status)
        }
    }

    /// Invokes a registered function with the provided payload.
    /// - Parameters:
    ///   - functionID: Identifier of the function to invoke.
    ///   - payload: JSON payload to forward to the function.
    /// - Returns: Invocation result payload as defined by the spec.
    public func invokeFunction(
        functionID: String,
        payload: InvocationRequestBody
    ) async throws -> InvocationResult {
        let output = try await client.invoke_function(
            .init(path: .init(function_id: functionID), body: .json(payload))
        )
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FunctionCallerClientError.missingResponseBody(operation: "invoke_function")
            }
            return body
        case .badRequest(let badRequest):
            if case let .json(error) = badRequest.body {
                throw FunctionCallerClientError.badRequest(error)
            }
            throw FunctionCallerClientError.missingResponseBody(operation: "invoke_function")
        case .notFound(let notFound):
            if case let .json(error) = notFound.body {
                throw FunctionCallerClientError.notFound(error)
            }
            throw FunctionCallerClientError.missingResponseBody(operation: "invoke_function")
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw FunctionCallerClientError.validationError(error)
            }
            throw FunctionCallerClientError.missingResponseBody(operation: "invoke_function")
        case .undocumented(let status, _):
            throw FunctionCallerClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches Prometheus metrics exposed by the Function Caller service.
    public func metrics() async throws -> String {
        let output = try await client.metrics_metrics_get(.init())
        switch output {
        case .ok(let ok):
            guard case let .plainText(body) = ok.body else {
                throw FunctionCallerClientError.missingResponseBody(operation: "metrics")
            }
            let data = try await Data(collecting: body, upTo: 1 * 1_048_576)
            guard let string = String(data: data, encoding: .utf8) else {
                throw FunctionCallerClientError.invalidPlainTextEncoding(operation: "metrics")
            }
            return string
        case .undocumented(let status, _):
            throw FunctionCallerClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
