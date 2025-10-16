import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIURLSession
import OpenAPIRuntime
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Convenience wrapper for the generated Gateway API client.
public struct GatewayClient: Sendable {

    /// Errors emitted by ``GatewayClient``.
    public enum GatewayClientError: Error, Sendable, Equatable {
        /// The gateway responded with a status code that is not modelled by the specification.
        case unexpectedStatus(code: Int)
        /// The expected JSON payload was not present in the response.
        case missingResponseBody(operation: String)
    }

    /// JSON payload returned by the `/health` endpoint.
    public typealias HealthPayload = OpenAPIObjectContainer
    /// Metrics payload keyed by metric name.
    public typealias MetricsPayload = [String: Int]

    private let client: Client

    /// Creates a client backed by ``URLSession``.
    /// - Parameters:
    ///   - baseURL: Gateway base URL.
    ///   - defaultHeaders: Headers injected into every request when missing.
    ///   - session: Optional session to use for requests. Defaults to `.shared`.
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: defaultHeaders)
        self.client = Client(
            serverURL: baseURL,
            transport: transport,
            middlewares: middlewares
        )
    }

    /// Creates a client backed by ``AsyncHTTPClient`` for server/Linux deployments.
    /// - Parameters:
    ///   - baseURL: Gateway base URL.
    ///   - httpClient: Async HTTP client used to execute requests.
    ///   - defaultHeaders: Headers injected into every request when missing.
    ///   - timeout: Optional per-request timeout.
    ///   - requestBodyMaxBytes: Maximum request body size buffered by the transport.
    ///   - responseBodyMaxBytes: Maximum response body size buffered by the transport.
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
        self.client = Client(
            serverURL: baseURL,
            transport: transport,
            middlewares: middlewares
        )
    }

    /// Returns the current gateway health payload.
    public func health() async throws -> HealthPayload {
        let output = try await client.gatewayHealth()
        switch output {
        case .ok(let ok):
            return try ok.body.json
        case .badRequest:
            throw GatewayClientError.unexpectedStatus(code: 400)
        case .undocumented(let status, _):
            throw GatewayClientError.unexpectedStatus(code: status)
        }
    }

    /// Returns gateway metrics as a JSON object keyed by metric name.
    public func metrics() async throws -> MetricsPayload {
        let output = try await client.gatewayMetrics()
        switch output {
        case .ok(let ok):
            let payload = try ok.body.json
            return payload.additionalProperties
        case .badRequest:
            throw GatewayClientError.unexpectedStatus(code: 400)
        case .undocumented(let status, _):
            throw GatewayClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
