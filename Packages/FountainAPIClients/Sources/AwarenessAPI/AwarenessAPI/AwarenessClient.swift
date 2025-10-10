import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// High-level wrapper for the Baseline Awareness API generated client.
public struct AwarenessClient: Sendable {

    /// Errors thrown by ``AwarenessClient`` when responses cannot be interpreted.
    public enum AwarenessClientError: Error, Sendable, Equatable {
        /// The service returned a status code that is not modelled by the specification.
        case unexpectedStatus(code: Int)
        /// The expected response body was missing or encoded using an unsupported format.
        case missingResponseBody(operation: String)
        /// Metrics responses could not be decoded as UTF-8 text.
        case invalidPlainTextEncoding(operation: String)
    }

    /// Alias for the JSON payload returned by the health endpoint.
    public typealias HealthPayload = Operations.health_health_get.Output.Ok.Body.jsonPayload
    /// Alias for responses returning generic JSON objects.
    public typealias GenericPayload = OpenAPIValueContainer
    /// Alias for the payload returned by `/corpus/history` analytics endpoint.
    public typealias HistoryAnalyticsPayload = Operations.listHistoryAnalytics.Output.Ok.Body.jsonPayload
    /// Alias for the payload returned by `/corpus/semantic-arc`.
    public typealias SemanticArcPayload = Operations.readSemanticArc.Output.Ok.Body.jsonPayload

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

    /// Returns the current health payload.
    public func health() async throws -> HealthPayload {
        let output = try await client.health_health_get(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "health_health_get")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Initializes a new corpus.
    public func initializeCorpus(
        _ request: Components.Schemas.InitIn
    ) async throws -> Components.Schemas.InitOut {
        let output = try await client.initializeCorpus(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "initializeCorpus")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Adds a baseline document to the corpus.
    public func addBaseline(
        _ request: Components.Schemas.BaselineRequest
    ) async throws -> GenericPayload {
        let output = try await client.addBaseline(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "addBaseline")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Adds a drift document to the corpus.
    public func addDrift(
        _ request: Components.Schemas.DriftRequest
    ) async throws -> GenericPayload {
        let output = try await client.addDrift(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "addDrift")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Adds narrative patterns to the corpus.
    public func addPatterns(
        _ request: Components.Schemas.PatternsRequest
    ) async throws -> GenericPayload {
        let output = try await client.addPatterns(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "addPatterns")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Adds a reflection item to the corpus.
    public func addReflection(
        _ request: Components.Schemas.ReflectionRequest
    ) async throws -> GenericPayload {
        let output = try await client.addReflection(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "addReflection")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Lists reflections for the specified corpus.
    public func listReflections(corpusID: String) async throws -> Components.Schemas.ReflectionSummaryResponse {
        let output = try await client.listReflections(.init(path: .init(corpus_id: corpusID)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "listReflections")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Lists history entries for the specified corpus.
    public func listHistory(corpusID: String) async throws -> Components.Schemas.HistorySummaryResponse {
        let output = try await client.listHistory(.init(path: .init(corpus_id: corpusID)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "listHistory")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Summarizes history for the specified corpus.
    public func summarizeHistory(corpusID: String) async throws -> Components.Schemas.HistorySummaryResponse {
        let output = try await client.summarizeHistory(.init(path: .init(corpus_id: corpusID)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "summarizeHistory")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Returns the analytics history payload for the given corpus.
    public func historyAnalytics(corpusID: String) async throws -> HistoryAnalyticsPayload {
        let query = Operations.listHistoryAnalytics.Input.Query(corpus_id: corpusID)
        let output = try await client.listHistoryAnalytics(.init(query: query))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "listHistoryAnalytics")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Returns the semantic arc payload for the given corpus.
    public func semanticArc(corpusID: String) async throws -> SemanticArcPayload {
        let query = Operations.readSemanticArc.Input.Query(corpus_id: corpusID)
        let output = try await client.readSemanticArc(.init(query: query))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "readSemanticArc")
            }
            return body
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches Prometheus metrics from the Awareness service.
    public func metrics() async throws -> String {
        let output = try await client.metrics_metrics_get(.init())
        switch output {
        case .ok(let ok):
            guard case let .plainText(body) = ok.body else {
                throw AwarenessClientError.missingResponseBody(operation: "metrics")
            }
            let data = try await Data(collecting: body, upTo: 1 * 1_048_576)
            guard let text = String(data: data, encoding: .utf8) else {
                throw AwarenessClientError.invalidPlainTextEncoding(operation: "metrics")
            }
            return text
        case .undocumented(let status, _):
            throw AwarenessClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
