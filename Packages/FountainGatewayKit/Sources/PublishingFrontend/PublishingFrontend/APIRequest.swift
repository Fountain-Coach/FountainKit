import Foundation

/// Empty body type used for requests without a payload.
public struct NoBody: Codable {}

/// Protocol describing an HTTP API request.
/// Conformers provide the HTTP method, endpoint path,
/// and optional encodable body type for the request.
/// The expected server response type is given by ``Response``.
public protocol APIRequest {
    /// Encodable payload sent with the request.
    /// Defaults to ``NoBody`` for endpoints without bodies.
    associatedtype Body: Encodable = NoBody
    /// Decodable type returned from the server.
    associatedtype Response: Decodable
    /// HTTP method such as ``GET`` or ``POST``.
    var method: String { get }
    /// Path relative to the API's base URL.
    var path: String { get }
    /// Optional body encoded as JSON for the request.
    var body: Body? { get }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
