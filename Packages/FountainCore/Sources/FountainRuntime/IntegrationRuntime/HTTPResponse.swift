import Foundation

/// Standard HTTP response returned by ``HTTPKernel`` handlers.
/// Provides mutable status, headers and response body.
public struct HTTPResponse: Sendable {
    /// HTTP status code sent back to the client.
    public var status: Int
    /// Headers included with the response.
    public var headers: [String: String]
    /// Raw payload returned as the message body.
    public var body: Data

    /// Creates a new response value.
    /// - Parameters:
    ///   - status: HTTP status code to return.
    ///   - headers: Headers for the response.
    ///   - body: Response body bytes.
    public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
