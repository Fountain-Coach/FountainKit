import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Convenience wrapper around the generated Bootstrap API client.
public struct BootstrapClient: Sendable {

    /// Errors thrown by ``BootstrapClient`` when responses cannot be interpreted.
    public enum BootstrapClientError: Error, Sendable, Equatable {
        /// The server returned a status code that is not modelled by the OpenAPI document.
        case unexpectedStatus(code: Int)
        /// The server reported a validation error (HTTP 422).
        case validationError(Components.Schemas.HTTPValidationError)
        /// The expected response body was missing or encoded using an unsupported format.
        case missingResponseBody(operation: String)
        /// Prometheus metrics responses could not be decoded as UTF-8 text.
        case invalidPlainTextEncoding(operation: String)
    }

    /// Alias for the JSON payload returned by `POST /bootstrap/baseline`.
    public typealias BaselineResponse = Operations.bootstrapAddBaseline.Output.Ok.Body.jsonPayload

    private let client: Client

    /// Creates a client that performs requests using ``URLSession``.
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

    /// Initializes a corpus by delegating to Awareness and seeding default roles.
    public func initializeCorpus(
        _ request: Components.Schemas.InitIn
    ) async throws -> Components.Schemas.InitOut {
        let output = try await client.bootstrapInitializeCorpus(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw BootstrapClientError.missingResponseBody(operation: "bootstrapInitializeCorpus")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw BootstrapClientError.validationError(error)
            }
            throw BootstrapClientError.missingResponseBody(operation: "bootstrapInitializeCorpus")
        case .undocumented(let status, _):
            throw BootstrapClientError.unexpectedStatus(code: status)
        }
    }

    /// Seeds GPT roles for an existing corpus.
    public func seedRoles(
        _ request: Components.Schemas.RoleInitRequest
    ) async throws -> Components.Schemas.RoleDefaults {
        let output = try await client.seedRoles(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw BootstrapClientError.missingResponseBody(operation: "seedRoles")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw BootstrapClientError.validationError(error)
            }
            throw BootstrapClientError.missingResponseBody(operation: "seedRoles")
        case .undocumented(let status, _):
            throw BootstrapClientError.unexpectedStatus(code: status)
        }
    }

    /// Seeds GPT roles via the bootstrap persona workflow.
    public func bootstrapSeedRoles(
        _ request: Components.Schemas.RoleInitRequest
    ) async throws -> Components.Schemas.RoleDefaults {
        let output = try await client.bootstrapSeedRoles(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw BootstrapClientError.missingResponseBody(operation: "bootstrapSeedRoles")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw BootstrapClientError.validationError(error)
            }
            throw BootstrapClientError.missingResponseBody(operation: "bootstrapSeedRoles")
        case .undocumented(let status, _):
            throw BootstrapClientError.unexpectedStatus(code: status)
        }
    }

    /// Adds a new baseline snapshot and triggers downstream analytics.
    public func addBaseline(
        _ request: Components.Schemas.BaselineIn
    ) async throws -> BaselineResponse {
        let output = try await client.bootstrapAddBaseline(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw BootstrapClientError.missingResponseBody(operation: "bootstrapAddBaseline")
            }
            return body
        case .unprocessableEntity(let entity):
            if case let .json(error) = entity.body {
                throw BootstrapClientError.validationError(error)
            }
            throw BootstrapClientError.missingResponseBody(operation: "bootstrapAddBaseline")
        case .undocumented(let status, _):
            throw BootstrapClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches Prometheus metrics from the Bootstrap service.
    public func metrics() async throws -> String {
        let output = try await client.metrics_metrics_get(.init())
        switch output {
        case .ok(let ok):
            guard case let .plainText(body) = ok.body else {
                throw BootstrapClientError.missingResponseBody(operation: "metrics")
            }
            let data = try await Data(collecting: body, upTo: 1 * 1_048_576)
            guard let text = String(data: data, encoding: .utf8) else {
                throw BootstrapClientError.invalidPlainTextEncoding(operation: "metrics")
            }
            return text
        case .undocumented(let status, _):
            throw BootstrapClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
