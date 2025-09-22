import Foundation
import FountainRuntime

/// Plugin exposing role health-check endpoints.
public struct RoleHealthCheckGatewayPlugin: Sendable {
    public let router: Router
    public init() {
        self.router = Router()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
