import Foundation
import AsyncHTTPClient
import NIOCore
import HTTPTypes
import NIOHTTP1
import OpenAPIRuntime

/// Transport bridging generated OpenAPI clients to ``AsyncHTTPClient``.
///
/// The transport eagerly buffers request and response bodies to simplify
/// integration while still honouring configurable size limits. It is primarily
/// intended for Linux environments where `URLSession` is unavailable or lacks
/// parity with Darwin's implementation.
public struct AsyncHTTPClientTransport: ClientTransport, Sendable {

    /// Errors emitted by the transport when adapting requests or responses.
    public enum Error: Swift.Error, Equatable, Sendable {
        /// The request path could not be combined with the provided base URL.
        case invalidRequestURL(path: String?, baseURL: URL)
    }

    /// Configuration for the transport.
    public struct Configuration: Sendable {
        /// Underlying async HTTP client used to execute requests.
        public var client: HTTPClient
        /// Optional timeout applied to each request.
        public var timeout: TimeAmount?
        /// Maximum request body size accepted when buffering (in bytes).
        public var requestBodyMaxBytes: Int
        /// Maximum response body size accepted when buffering (in bytes).
        public var responseBodyMaxBytes: Int

        /// Default request body buffer limit (2 MiB).
        public static let defaultRequestBodyMaxBytes = 2 * 1_048_576
        /// Default response body buffer limit (8 MiB).
        public static let defaultResponseBodyMaxBytes = 8 * 1_048_576

        /// Creates a new configuration.
        /// - Parameters:
        ///   - client: Async HTTP client to execute requests with.
        ///   - timeout: Optional request timeout.
        ///   - requestBodyMaxBytes: Request body buffering limit (defaults to 2 MiB).
        ///   - responseBodyMaxBytes: Response body buffering limit (defaults to 8 MiB).
        public init(
            client: HTTPClient,
            timeout: TimeAmount? = nil,
            requestBodyMaxBytes: Int = Self.defaultRequestBodyMaxBytes,
            responseBodyMaxBytes: Int = Self.defaultResponseBodyMaxBytes
        ) {
            self.client = client
            self.timeout = timeout
            self.requestBodyMaxBytes = requestBodyMaxBytes
            self.responseBodyMaxBytes = responseBodyMaxBytes
        }
    }

    private let configuration: Configuration
    private let allocator = ByteBufferAllocator()

    /// Creates a transport from the given configuration.
    /// - Parameter configuration: Transport configuration parameters.
    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Convenience initializer using explicit parameters.
    public init(
        client: HTTPClient,
        timeout: TimeAmount? = nil,
        requestBodyMaxBytes: Int = Configuration.defaultRequestBodyMaxBytes,
        responseBodyMaxBytes: Int = Configuration.defaultResponseBodyMaxBytes
    ) {
        self.init(
            configuration: .init(
                client: client,
                timeout: timeout,
                requestBodyMaxBytes: requestBodyMaxBytes,
                responseBodyMaxBytes: responseBodyMaxBytes
            )
        )
    }

    public func send(
        _ request: HTTPRequest,
        body requestBody: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var httpRequest = HTTPClientRequest(url: try makeURLString(for: request, baseURL: baseURL))
        httpRequest.method = .init(rawValue: request.method.rawValue)
        httpRequest.headers = makeHeaders(from: request.headerFields)
        if let body = requestBody {
            httpRequest.body = try await makeRequestBody(body)
        }

        let timeout = configuration.timeout ?? .seconds(30)
        let response = try await configuration.client.execute(httpRequest, timeout: timeout)

        var httpResponse = HTTPResponse(status: .init(code: Int(response.status.code)))
        httpResponse.headerFields.reserveCapacity(response.headers.count)
        for (name, value) in response.headers {
            guard let fieldName = HTTPField.Name(name) else { continue }
            httpResponse.headerFields.append(HTTPField(name: fieldName, value: value))
        }

        let body = try await makeResponseBody(response.body, headers: response.headers)
        return (httpResponse, body)
    }

    private func makeURLString(for request: HTTPRequest, baseURL: URL) throws -> String {
        guard var baseComponents = URLComponents(string: baseURL.absoluteString) else {
            throw Error.invalidRequestURL(path: request.path, baseURL: baseURL)
        }
        let path = request.path ?? ""
        guard let requestComponents = URLComponents(string: path) else {
            throw Error.invalidRequestURL(path: request.path, baseURL: baseURL)
        }
        let encodedPath = requestComponents.percentEncodedPath
        baseComponents.percentEncodedPath += encodedPath
        baseComponents.percentEncodedQuery = requestComponents.percentEncodedQuery
        guard let url = baseComponents.url else {
            throw Error.invalidRequestURL(path: request.path, baseURL: baseURL)
        }
        return url.absoluteString
    }

    private func makeHeaders(from fields: HTTPFields) -> HTTPHeaders {
        var merged: [HTTPField.Name: String] = [:]
        merged.reserveCapacity(fields.count)
        for field in fields {
            if let existing = merged[field.name] {
                let separator = field.name == .cookie ? "; " : ", "
                merged[field.name] = "\(existing)\(separator)\(field.value)"
            } else {
                merged[field.name] = field.value
            }
        }
        var headers = HTTPHeaders()
        headers.reserveCapacity(merged.count)
        for (name, value) in merged.sorted(by: { $0.key.rawName < $1.key.rawName }) {
            headers.add(name: name.rawName, value: value)
        }
        return headers
    }

    private func makeRequestBody(_ body: HTTPBody) async throws -> HTTPClientRequest.Body {
        let data = try await Data(collecting: body, upTo: configuration.requestBodyMaxBytes)
        var buffer = allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        return .bytes(buffer)
    }

    private func makeResponseBody(_ body: HTTPClientResponse.Body, headers: HTTPHeaders) async throws -> HTTPBody? {
        let buffer = try await body.collect(upTo: configuration.responseBodyMaxBytes)
        guard buffer.readableBytes > 0 else { return nil }
        let length: HTTPBody.Length
        if let lengthHeader = headers.first(name: "content-length"), let value = Int64(lengthHeader) {
            length = .known(value)
        } else {
            length = .unknown
        }
        let bytes = ArraySlice(buffer.readableBytesView)
        return HTTPBody(bytes, length: length)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
