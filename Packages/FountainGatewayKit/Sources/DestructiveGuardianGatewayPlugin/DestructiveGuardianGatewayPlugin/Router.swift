import Foundation
import FountainRuntime

/// Router for destructive guardian endpoints.
public struct Router: Sendable {
    public var handlers: Handlers

    public init(handlers: Handlers) {
        self.handlers = handlers
    }

    /// Routes requests to handlers.
    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("POST", "/guardian/evaluate"):
            let body = try? JSONDecoder().decode(GuardianEvaluateRequest.self, from: request.body)
            return try await handlers.guardianEvaluate(request, body: body)
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
