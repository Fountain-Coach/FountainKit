import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction over ``URLSession`` for easier testing.
public protocol HTTPSession {
    /// Performs the given request and returns the server response.
    /// - Parameter request: Request to execute.
    /// - Returns: The response data and URL response.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {
    /// Conformance allowing ``APIClient`` to depend on ``HTTPSession``.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await self.data(for: request, delegate: nil)
    }
}

/// Representation of an error returned by an API request.
/// Decodes a JSON body of the form `{ "error": "message" }` and
/// carries the associated HTTP status code.
public struct APIError: Error, Decodable {
    /// HTTP status code returned by the server.
    public let status: Int
    /// Error message parsed from the server response.
    public let message: String

    private enum CodingKeys: String, CodingKey { case message = "error" }

    /// Creates an instance with an explicit status code and message.
    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    /// Decodes the `error` field from the response body.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = 0
        self.message = try container.decode(String.self, forKey: .message)
    }
}

/// Minimal HTTP client for executing ``APIRequest`` values.
public struct APIClient {
    /// Root endpoint used for all requests.
    let baseURL: URL
    /// Transport layer performing network calls.
    let session: HTTPSession
    /// Headers automatically attached to every request.
    let defaultHeaders: [String: String]

    /// Creates a new client with optional session and headers.
    /// - Parameters:
    ///   - baseURL: Base API endpoint.
    ///   - session: Underlying HTTP session implementation.
    ///   - defaultHeaders: Headers applied to every request.
    public init(baseURL: URL, session: HTTPSession = URLSession.shared, defaultHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.session = session
        self.defaultHeaders = defaultHeaders
    }

    /// Executes an ``APIRequest`` and decodes the server response.
    /// When ``R.Response`` is ``Data``, the raw bytes are returned directly.
    /// If ``R.Response`` is ``NoBody``, the response payload is discarded and an empty instance is provided.
    /// - Parameter request: The request to perform.
    /// - Returns: The decoded response value for ``R.Response``.
    public func send<R: APIRequest>(_ request: R) async throws -> R.Response {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(request.path))
        urlRequest.httpMethod = request.method
        for (header, value) in defaultHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }
        if let body = request.body {
            urlRequest.httpBody = try JSONEncoder().encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let decoded = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIError(status: http.statusCode, message: decoded.message)
            } else {
                throw APIError(status: http.statusCode, message: String(decoding: data, as: UTF8.self))
            }
        }
        if R.Response.self == Data.self {
            return data as! R.Response
        }
        if R.Response.self == NoBody.self {
            return NoBody() as! R.Response
        }
        return try JSONDecoder().decode(R.Response.self, from: data)
    }
}

public extension APIClient {
    /// Convenience initializer using a bearer token for authorization.
    /// - Parameters:
    ///   - baseURL: Base API endpoint.
    ///   - bearerToken: Token inserted as the `Authorization` header.
    ///   - session: Optional custom session.
    init(baseURL: URL, bearerToken: String, session: HTTPSession = URLSession.shared) {
        self.init(baseURL: baseURL, session: session, defaultHeaders: ["Authorization": "Bearer \(bearerToken)"])
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
