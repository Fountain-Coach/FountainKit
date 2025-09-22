import Foundation
import FountainRuntime

/// Router for auth gateway endpoints.
public struct Router: Sendable {
    public var handlers: Handlers
    public init(handlers: Handlers = Handlers()) { self.handlers = handlers }

    /// Routes requests to handlers.
    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("POST", "/auth/validate"):
            let body = try? JSONDecoder().decode(ValidateRequest.self, from: request.body)
            return try await handlers.authValidate(request, body: body)
        case ("POST", "/auth/claims"), ("GET", "/auth/claims"):
            return try await handlers.authClaims(request, body: nil)
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
