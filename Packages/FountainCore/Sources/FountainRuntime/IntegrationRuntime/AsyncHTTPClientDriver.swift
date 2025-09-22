import AsyncHTTPClient
import NIOCore
import NIOHTTP1

/// HTTP client adapter backed by ``AsyncHTTPClient``.
///
/// This driver conforms to ``HTTPClientProtocol`` by forwarding requests
/// to an instance of ``AsyncHTTPClient``. It is mainly used in tests and
/// generated clients where a lightweight, event-loop based HTTP client
/// is desirable.
public final class AsyncHTTPClientDriver: HTTPClientProtocol, @unchecked Sendable {
    /// Underlying async HTTP client used for requests.
    let client: HTTPClient

    /// Creates a new driver wrapping ``HTTPClient``.
    /// - Parameter eventLoopGroupProvider: Event loop provider for the client.
    public init(eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider = .singleton) {
        self.client = HTTPClient(eventLoopGroupProvider: eventLoopGroupProvider)
    }

    /// Executes an HTTP request and returns the response payload and headers.
    ///
    /// Any networking or decoding failures are surfaced to the caller allowing
    /// tests to verify proper error handling behavior.
    /// - Parameters:
    ///   - method: HTTP verb to use when contacting the server.
    ///   - url: Absolute URL string of the resource.
    ///   - headers: Request headers to send.
    ///   - body: Optional request body buffer.
    /// - Returns: Tuple containing the response body and header fields.
    /// - Throws: If the request cannot be executed or a network error occurs.
    public func execute(method: HTTPMethod, url: String, headers: HTTPHeaders = HTTPHeaders(), body: ByteBuffer?) async throws -> (ByteBuffer, HTTPHeaders) {
        var request = HTTPClientRequest(url: url)
        request.method = method
        request.headers = headers
        if let body = body {
            request.body = .bytes(body)
        }
        let response = try await client.execute(request, timeout: .seconds(5))
        let bytes = try await response.body.collect(upTo: 1 << 20)
        return (bytes, response.headers)
    }

    /// Gracefully shuts down the underlying client.
    /// Call this after all requests complete to free resources.
    public func shutdown() async throws {
        try await client.shutdown()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
