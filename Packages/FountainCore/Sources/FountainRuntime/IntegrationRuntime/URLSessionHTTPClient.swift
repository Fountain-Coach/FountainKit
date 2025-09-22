import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1

/// Simple HTTP client backed by ``URLSession``.
public struct URLSessionHTTPClient: HTTPClientProtocol {
    /// ``URLSession`` instance used to perform requests.
    let session: URLSession

    /// Creates a new client with the provided session.
    /// - Parameter session: The session to send requests with.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Performs an HTTP request using `URLSession`.
    /// - Parameters:
    ///   - method: HTTP method to execute.
    ///   - url: Target URL string.
    ///   - headers: Headers for the request.
    ///   - body: Optional request payload.
    /// - Returns: A tuple of response body and headers.
    public func execute(method: HTTPMethod, url: String, headers: HTTPHeaders = HTTPHeaders(), body: ByteBuffer?) async throws -> (ByteBuffer, HTTPHeaders) {
        guard let requestURL = URL(string: url), requestURL.scheme != nil else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method.rawValue
        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.name)
        }
        if let body = body {
            request.httpBody = Data(body.readableBytesView)
        }
        let (data, response) = try await session.data(for: request)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        var respHeaders = HTTPHeaders()
        if let http = response as? HTTPURLResponse {
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String { respHeaders.add(name: k, value: v) }
            }
        }
        return (buffer, respHeaders)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
