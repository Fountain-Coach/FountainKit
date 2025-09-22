import Foundation
import FountainRuntime

/// Plugin providing auth validation and claims endpoints.
public struct AuthGatewayPlugin: Sendable {
    public let router: Router

    /// Creates a plugin with the supplied router. Defaults to a router with
    /// a fresh set of handlers.
    public init(router: Router = Router()) {
        self.router = router
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
