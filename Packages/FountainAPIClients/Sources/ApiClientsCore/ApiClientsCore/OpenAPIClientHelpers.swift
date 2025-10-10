import Foundation
import OpenAPIRuntime
import HTTPTypes

/// Helpers for configuring generated OpenAPI clients within the API clients package.
public enum APIClientHelpers {
    /// Middleware injecting default headers when missing from an outgoing request.
    public struct DefaultHeadersMiddleware: ClientMiddleware, @unchecked Sendable {
        private let headers: [(HTTPField.Name, String)]

        public init(_ headers: [String: String]) {
            self.headers = headers.compactMap { key, value in
                HTTPField.Name(key).map { ($0, value) }
            }
        }

        public func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID: String,
            next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
        ) async throws -> (HTTPResponse, HTTPBody?) {
            guard !headers.isEmpty else { return try await next(request, body, baseURL) }
            var req = request
            for (name, value) in headers where req.headerFields[name] == nil {
                req.headerFields[name] = value
            }
            return try await next(req, body, baseURL)
        }
    }

    /// Produces the default middleware chain for generated clients.
    /// - Parameter defaultHeaders: Header dictionary to inject when missing.
    /// - Returns: Array of middlewares to provide to generated clients.
    public static func defaultMiddlewares(defaultHeaders: [String: String] = [:]) -> [any ClientMiddleware] {
        guard !defaultHeaders.isEmpty else { return [] }
        return [DefaultHeadersMiddleware(defaultHeaders)]
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
