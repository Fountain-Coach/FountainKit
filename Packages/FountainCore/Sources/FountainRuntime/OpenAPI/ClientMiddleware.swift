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
            _ request: HTTPTypes.HTTPRequest,
            body: OpenAPIRuntime.HTTPBody?,
            baseURL: URL,
            operationID: String,
            next: @Sendable (HTTPTypes.HTTPRequest, OpenAPIRuntime.HTTPBody?, URL) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?)
        ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {
            // Only add header if not already present on the request.
            var req = request
            var reqBody = body
            for (name, value) in headers where req.headerFields[name] == nil {
                req.headerFields[name] = value
            }
            return try await next(req, reqBody, baseURL)
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
