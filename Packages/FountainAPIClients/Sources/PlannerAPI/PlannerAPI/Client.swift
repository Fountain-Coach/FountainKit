import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Convenience wrapper around the generated Planner API client.
///
/// The wrapper exposes async methods that return strongly typed models while
/// supporting both `URLSession` and `AsyncHTTPClient` transports to satisfy the
/// implementation plan's cross-platform requirements.
public struct PlannerClient: Sendable {

    /// Errors thrown by ``PlannerClient`` when responses cannot be handled.
    public enum PlannerClientError: Error, Sendable {
        /// The server returned a status code that is not explicitly modelled.
        case unexpectedStatus(code: Int)
        /// The server reported a validation error (HTTP 422).
        case validationError(Components.Schemas.HTTPValidationError)
        /// The expected response body was missing or used an unsupported format.
        case missingResponseBody(operation: String)
        /// Text responses could not be decoded using UTF-8.
        case invalidPlainTextEncoding(operation: String)
    }

    /// Alias describing the semantic arc payload returned by the API.
    public typealias SemanticArcPayload = Operations.get_semantic_arc.Output.Ok.Body.jsonPayload

    /// Alias describing the corpora list payload returned by the API.
    public typealias CorporaListPayload = Operations.planner_list_corpora.Output.Ok.Body.jsonPayload

    private let client: Client

    /// Creates a client that performs requests using ``URLSession``.
    /// - Parameters:
    ///   - baseURL: Base URL of the Planner service.
    ///   - defaultHeaders: Optional default headers applied when missing.
    ///   - session: URLSession instance to use (defaults to `.shared`).
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: defaultHeaders)
        self.client = Client(serverURL: baseURL, transport: transport, middlewares: middlewares)
    }

    /// Creates a client backed by ``AsyncHTTPClient`` for server and Linux use.
    /// - Parameters:
    ///   - baseURL: Base URL of the Planner service.
    ///   - httpClient: Shared AsyncHTTPClient instance.
    ///   - defaultHeaders: Optional headers applied when missing.
    ///   - timeout: Optional request timeout.
    ///   - requestBodyMaxBytes: Request buffering limit (defaults to 2 MiB).
    ///   - responseBodyMaxBytes: Response buffering limit (defaults to 8 MiB).
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

    /// Generates a plan for the provided objective.
    /// - Parameter objective: High-level user objective to plan for.
    /// - Returns: The generated plan response.
    public func reason(objective: String) async throws -> Components.Schemas.PlanResponse {
        let request = Components.Schemas.UserObjectiveRequest(objective: objective)
        return try await reason(request)
    }

    /// Generates a plan for the provided request payload.
    /// - Parameter request: Objective payload describing the desired plan.
    /// - Returns: The generated plan response from the API.
    public func reason(_ request: Components.Schemas.UserObjectiveRequest) async throws -> Components.Schemas.PlanResponse {
        let output = try await client.planner_reason(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "planner_reason")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw PlannerClientError.validationError(error)
            }
            throw PlannerClientError.missingResponseBody(operation: "planner_reason")
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }

    /// Executes a previously generated plan.
    /// - Parameter request: Execution payload containing the steps to run.
    /// - Returns: Execution results for each step in the plan.
    public func execute(_ request: Components.Schemas.PlanExecutionRequest) async throws -> Components.Schemas.ExecutionResult {
        let output = try await client.planner_execute(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "planner_execute")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw PlannerClientError.validationError(error)
            }
            throw PlannerClientError.missingResponseBody(operation: "planner_execute")
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }

    /// Lists the corpora known to the planner service.
    /// - Returns: Array of corpus identifiers.
    public func listCorpora() async throws -> [String] {
        let output = try await client.planner_list_corpora(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "planner_list_corpora")
            }
            return Array(body)
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches the stored reflection history for the given corpus identifier.
    /// - Parameter corpusId: Identifier of the corpus whose reflections should be returned.
    /// - Returns: Reflection history response payload.
    public func reflectionHistory(corpusId: String) async throws -> Components.Schemas.HistoryListResponse {
        let output = try await client.get_reflection_history(.init(path: .init(corpus_id: corpusId)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "get_reflection_history")
            }
            return body
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches the semantic arc summary for the given corpus identifier.
    /// - Parameter corpusId: Identifier of the corpus whose semantic arc should be returned.
    /// - Returns: Semantic arc payload as defined by the OpenAPI specification.
    public func semanticArc(corpusId: String) async throws -> SemanticArcPayload {
        let output = try await client.get_semantic_arc(.init(path: .init(corpus_id: corpusId)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "get_semantic_arc")
            }
            return body
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }

    /// Adds a new reflection to the specified corpus.
    /// - Parameter request: Reflection payload to persist.
    /// - Returns: The stored reflection item returned by the service.
    public func addReflection(_ request: Components.Schemas.ChatReflectionRequest) async throws -> Components.Schemas.ReflectionItem {
        let output = try await client.post_reflection(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "post_reflection")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw PlannerClientError.validationError(error)
            }
            throw PlannerClientError.missingResponseBody(operation: "post_reflection")
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches Prometheus metrics from the Planner service.
    /// - Returns: Metrics text encoded using UTF-8.
    public func metrics() async throws -> String {
        let output = try await client.metrics_metrics_get(.init())
        switch output {
        case .ok(let ok):
            guard case let .plainText(body) = ok.body else {
                throw PlannerClientError.missingResponseBody(operation: "metrics")
            }
            let data = try await Data(collecting: body, upTo: 1 * 1_048_576)
            guard let string = String(data: data, encoding: .utf8) else {
                throw PlannerClientError.invalidPlainTextEncoding(operation: "metrics")
            }
            return string
        case .undocumented(let status, _):
            throw PlannerClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
