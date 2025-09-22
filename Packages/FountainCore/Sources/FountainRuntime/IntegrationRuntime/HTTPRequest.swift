import Foundation

/// Placeholder type representing an empty request body.
public struct NoBody: Codable {}

/// Represents an HTTP request flowing through ``HTTPKernel`` powered servers.
/// Stores the HTTP method, path, headers and optional body data.
public struct HTTPRequest: Sendable {
    /// HTTP verb such as `GET` or `POST`.
    public let method: String
    /// Requested path without scheme or host.
    public let path: String
    /// HTTP headers associated with the request.
    public var headers: [String: String]
    /// Optional message body data.
    public var body: Data

    /// Creates a new request instance.
    /// - Parameters:
    ///   - method: HTTP verb such as `GET` or `POST`.
    ///   - path: Requested resource path.
    ///   - headers: HTTP headers to include.
    ///   - body: Optional payload data.
    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
