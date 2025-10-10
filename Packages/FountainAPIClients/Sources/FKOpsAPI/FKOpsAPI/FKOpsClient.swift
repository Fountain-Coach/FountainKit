import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wrapper around the generated FK Ops API client.
public struct FKOpsClient: Sendable {

    /// Errors surfaced when FK Ops responses cannot be decoded.
    public enum FKOpsClientError: Error, Sendable, Equatable {
        /// The service returned a status code not modelled in the OpenAPI document.
        case unexpectedStatus(code: Int)
        /// The expected response payload was missing or used an unexpected content type.
        case missingResponseBody(operation: String)
        /// Plain-text responses could not be decoded as UTF-8.
        case invalidPlainTextEncoding(operation: String)
    }

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

    /// Fetches the aggregate status of FountainKit services.
    public func status() async throws -> Components.Schemas.FKStatus {
        let output = try await client.fkStatus(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FKOpsClientError.missingResponseBody(operation: "fkStatus")
            }
            return body
        case .undocumented(let status, _):
            throw FKOpsClientError.unexpectedStatus(code: status)
        }
    }

    /// Triggers a workspace build.
    public func build() async throws -> Components.Schemas.Ack {
        let output = try await client.fkBuild(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FKOpsClientError.missingResponseBody(operation: "fkBuild")
            }
            return body
        case .undocumented(let status, _):
            throw FKOpsClientError.unexpectedStatus(code: status)
        }
    }

    /// Starts FountainKit core services.
    public func up() async throws -> Components.Schemas.Ack {
        let output = try await client.fkUp(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FKOpsClientError.missingResponseBody(operation: "fkUp")
            }
            return body
        case .undocumented(let status, _):
            throw FKOpsClientError.unexpectedStatus(code: status)
        }
    }

    /// Stops FountainKit core services.
    public func down() async throws -> Components.Schemas.Ack {
        let output = try await client.fkDown(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw FKOpsClientError.missingResponseBody(operation: "fkDown")
            }
            return body
        case .undocumented(let status, _):
            throw FKOpsClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches the most recent logs for the specified service.
    public func logs(service: String, lines: Int? = nil) async throws -> String {
        let query = Operations.fkLogs.Input.Query(service: service, lines: lines.map(Int32.init))
        let output = try await client.fkLogs(.init(query: query))
        switch output {
        case .ok(let ok):
            guard case let .plainText(body) = ok.body else {
                throw FKOpsClientError.missingResponseBody(operation: "fkLogs")
            }
            let data = try await Data(collecting: body, upTo: 2 * 1_048_576)
            guard let text = String(data: data, encoding: .utf8) else {
                throw FKOpsClientError.invalidPlainTextEncoding(operation: "fkLogs")
            }
            return text
        case .undocumented(let status, _):
            throw FKOpsClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
