import Foundation
import FountainRuntime

/// Router for rate limiter gateway endpoints.
public struct Router: Sendable {
    public var handlers: Handlers
    public init(handlers: Handlers = Handlers()) { self.handlers = handlers }

    /// Routes requests to handlers.
    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("POST", "/rate-limit/check"):
            let body = try? JSONDecoder().decode(RateLimitCheckRequest.self, from: request.body)
            return try await handlers.rateLimitCheck(request, body: body)
        case ("GET", "/rate-limit/stats"):
            return try await handlers.rateLimitStats(request, body: nil)
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
