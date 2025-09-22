import Foundation
import FountainRuntime

/// Routes role health-check requests to their handlers.
public struct Router: Sendable {
    public var handlers: Handlers
    public init(handlers: Handlers = Handlers()) { self.handlers = handlers }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("POST", "/role-health-check/reflect"):
            let body = try? JSONDecoder().decode(RoleHealthCheckRequest.self, from: request.body)
            return try await handlers.roleHealthCheckReflect(request, body: body)
        case ("POST", "/role-health-check/promote"):
            let body = try? JSONDecoder().decode(RoleHealthCheckRequest.self, from: request.body)
            return try await handlers.roleHealthCheckPromote(request, body: body)
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
