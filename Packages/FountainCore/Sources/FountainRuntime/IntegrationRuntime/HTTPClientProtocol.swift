import NIOCore
import NIOHTTP1

/// Abstract HTTP client used by generated clients and servers.
public protocol HTTPClientProtocol {
    /// Executes a request and returns the response body and headers.
    /// - Parameters:
    ///   - method: HTTP method string.
    ///   - url: Absolute request URL.
    ///   - headers: Additional HTTP headers.
    ///   - body: Optional request body.
    func execute(method: HTTPMethod, url: String, headers: HTTPHeaders, body: ByteBuffer?) async throws -> (ByteBuffer, HTTPHeaders)
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
