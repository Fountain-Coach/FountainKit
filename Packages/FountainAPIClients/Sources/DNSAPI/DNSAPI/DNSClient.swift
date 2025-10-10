import Foundation
import AsyncHTTPClient
import NIOCore
import OpenAPIURLSession
import ApiClientsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// High-level convenience wrapper around the generated DNS API client.
///
/// The wrapper provides URLSession and AsyncHTTPClient initializers to satisfy
/// the implementation plan's cross-platform transport requirements while
/// returning strongly typed models for consumers.
public struct DNSClient: Sendable {

    /// Errors raised when DNS API responses cannot be handled.
    public enum DNSClientError: Error, Equatable, Sendable {
        /// The server returned a status code that is not modelled by the client.
        case unexpectedStatus(code: Int)
        /// The server omitted an expected JSON payload.
        case missingResponseBody(operation: String)
    }

    private let client: Client

    /// Creates a client that performs requests using `URLSession`.
    /// - Parameters:
    ///   - baseURL: Base URL of the DNS service.
    ///   - defaultHeaders: Optional headers added when absent on requests.
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

    /// Creates a client backed by `AsyncHTTPClient` for Linux and server use.
    /// - Parameters:
    ///   - baseURL: Base URL of the DNS service.
    ///   - httpClient: Shared AsyncHTTPClient instance.
    ///   - defaultHeaders: Optional headers added when absent on requests.
    ///   - timeout: Optional per-request timeout.
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

    /// Lists all managed DNS zones.
    public func listZones() async throws -> [Components.Schemas.Zone] {
        let output = try await client.listZones(.init())
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw DNSClientError.missingResponseBody(operation: "listZones")
            }
            return body.zones
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }

    /// Creates a new DNS zone.
    /// - Parameter name: Desired zone name (e.g. "example.test").
    /// - Returns: The created zone record.
    public func createZone(name: String) async throws -> Components.Schemas.Zone {
        let payload = Components.Schemas.ZoneCreateRequest(name: name)
        let output = try await client.createZone(.init(body: .json(payload)))
        switch output {
        case .created(let created):
            guard case let .json(zone) = created.body else {
                throw DNSClientError.missingResponseBody(operation: "createZone")
            }
            return zone
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }

    /// Deletes an existing DNS zone.
    /// - Parameter zoneId: Identifier of the zone to delete.
    public func deleteZone(zoneId: String) async throws {
        let output = try await client.deleteZone(.init(path: .init(zoneId: zoneId)))
        switch output {
        case .noContent:
            return
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }

    /// Lists all DNS records within the specified zone.
    /// - Parameter zoneId: Identifier of the zone whose records should be returned.
    public func listRecords(zoneId: String) async throws -> [Components.Schemas.Record] {
        let output = try await client.listRecords(.init(path: .init(zoneId: zoneId)))
        switch output {
        case .ok(let ok):
            guard case let .json(body) = ok.body else {
                throw DNSClientError.missingResponseBody(operation: "listRecords")
            }
            return body.records
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }

    /// Creates a DNS record inside the specified zone.
    /// - Parameters:
    ///   - zoneId: Identifier of the zone to modify.
    ///   - record: Record payload describing the desired DNS entry.
    /// - Returns: The persisted DNS record returned by the API.
    public func createRecord(
        zoneId: String,
        record: Components.Schemas.RecordRequest
    ) async throws -> Components.Schemas.Record {
        let output = try await client.createRecord(
            .init(path: .init(zoneId: zoneId), body: .json(record))
        )
        switch output {
        case .created(let created):
            guard case let .json(record) = created.body else {
                throw DNSClientError.missingResponseBody(operation: "createRecord")
            }
            return record
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }

    /// Updates an existing DNS record.
    /// - Parameters:
    ///   - zoneId: Identifier of the zone containing the record.
    ///   - recordId: Identifier of the record to update.
    ///   - record: Updated record payload.
    /// - Returns: The updated record returned by the service.
    public func updateRecord(
        zoneId: String,
        recordId: String,
        record: Components.Schemas.RecordRequest
    ) async throws -> Components.Schemas.Record {
        let output = try await client.updateRecord(
            .init(path: .init(zoneId: zoneId, recordId: recordId), body: .json(record))
        )
        switch output {
        case .ok(let ok):
            guard case let .json(record) = ok.body else {
                throw DNSClientError.missingResponseBody(operation: "updateRecord")
            }
            return record
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }

    /// Deletes a DNS record from the specified zone.
    /// - Parameters:
    ///   - zoneId: Identifier of the zone containing the record.
    ///   - recordId: Identifier of the record to remove.
    public func deleteRecord(zoneId: String, recordId: String) async throws {
        let output = try await client.deleteRecord(
            .init(path: .init(zoneId: zoneId, recordId: recordId))
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let status, _):
            throw DNSClientError.unexpectedStatus(code: status)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
