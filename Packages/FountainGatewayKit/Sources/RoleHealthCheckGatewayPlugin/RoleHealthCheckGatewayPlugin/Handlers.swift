import Foundation
import FountainRuntime

/// Handlers for role health-check routes.
public actor Handlers {
    public init() {}

    /// Enqueue a role health-check reflection.
    public func roleHealthCheckReflect(_ request: HTTPRequest, body: RoleHealthCheckRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 422) }
        let info = RoleInfo(name: body.roleName, prompt: "reflected")
        let data = try JSONEncoder().encode(info)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// Promote the latest role health-check reflection.
    public func roleHealthCheckPromote(_ request: HTTPRequest, body: RoleHealthCheckRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 422) }
        let info = RoleInfo(name: body.roleName, prompt: "promoted")
        let data = try JSONEncoder().encode(info)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
