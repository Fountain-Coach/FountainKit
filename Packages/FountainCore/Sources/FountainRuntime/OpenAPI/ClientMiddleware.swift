import Foundation
import OpenAPIRuntime
import HTTPTypes

/// Common client middlewares and helpers for generated OpenAPI clients.
public enum OpenAPIClientFactory {}

extension OpenAPIClientFactory {
    /// A client middleware that injects default HTTP headers if they are not already present.
    public struct DefaultHeadersMiddleware: ClientMiddleware, @unchecked Sendable {
        private let headers: [(HTTPField.Name, String)]

        /// Create a middleware that sets the given headers by default.
        /// - Parameter headers: Dictionary of header name → value. Existing request values are preserved.
        public init(_ headers: [String: String]) {
            self.headers = headers.compactMap { (k, v) in
                HTTPField.Name(k).map { ($0, v) }
            }
        }

        public func intercept(
            _ request: inout ClientRequest,
            baseURL: URL,
            operationID: String,
            next: (inout ClientRequest, URL) async throws -> ClientResponse
        ) async throws -> ClientResponse {
            // Only add header if not already present on the request.
            for (name, value) in headers where request.headerFields[name] == nil {
                request.headerFields.append(HTTPField(name: name, value: value))
            }
            return try await next(&request, baseURL)
        }
    }

    /// Build a list of default middlewares for clients.
    /// Currently includes only default headers injection; extend as needed.
    /// - Parameter defaultHeaders: Header dictionary to set when missing.
    /// - Returns: Array of client middlewares.
    public static func defaultMiddlewares(defaultHeaders: [String: String] = [:]) -> [any ClientMiddleware] {
        var mws: [any ClientMiddleware] = []
        if !defaultHeaders.isEmpty {
            mws.append(DefaultHeadersMiddleware(defaultHeaders))
        }
        return mws
    }
}

