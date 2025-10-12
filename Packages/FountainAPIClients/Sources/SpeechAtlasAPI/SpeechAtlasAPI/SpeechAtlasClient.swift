import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Convenience wrapper for interacting with the Speech Atlas endpoints derived from the Four Stars corpus.
public struct SpeechAtlasClient: Sendable {

    public enum SpeechAtlasClientError: Error, Sendable, Equatable {
        case unexpectedStatus(code: Int)
        case missingResponseBody(operation: String)
    }

    private let client: Client

    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: defaultHeaders)
        self.client = Client(serverURL: baseURL, transport: transport, middlewares: middlewares)
    }

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

    /// Lists speeches using optional metadata filters.
    public func listSpeeches(
        filters: Components.Schemas.SpeechesListRequest
    ) async throws -> Components.Schemas.SpeechList {
        let response = try await client.speechesList(.init(body: .json(filters)))
        switch response {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw SpeechAtlasClientError.missingResponseBody(operation: "speechesList")
            }
            return body.result
        case .badRequest:
            throw SpeechAtlasClientError.unexpectedStatus(code: 400)
        case .undocumented(let status, _):
            throw SpeechAtlasClientError.unexpectedStatus(code: status)
        }
    }

    /// Fetches a single speech, optionally including neighbouring context.
    public func fetchSpeech(
        request: Components.Schemas.SpeechesDetailRequest
    ) async throws -> Components.Schemas.SpeechDetail {
        let response = try await client.speechesDetail(.init(body: .json(request)))
        switch response {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw SpeechAtlasClientError.missingResponseBody(operation: "speechesDetail")
            }
            return body.result
        case .badRequest:
            throw SpeechAtlasClientError.unexpectedStatus(code: 400)
        case .undocumented(let status, _):
            throw SpeechAtlasClientError.unexpectedStatus(code: status)
        }
    }

    /// Aggregates a group of speeches into a deterministic summary.
    public func summariseSpeeches(
        request: Components.Schemas.SpeechesSummaryRequest
    ) async throws -> Components.Schemas.SpeechSummary {
        let response = try await client.speechesSummary(.init(body: .json(request)))
        switch response {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw SpeechAtlasClientError.missingResponseBody(operation: "speechesSummary")
            }
            return body.result
        case .badRequest:
            throw SpeechAtlasClientError.unexpectedStatus(code: 400)
        case .undocumented(let status, _):
            throw SpeechAtlasClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
