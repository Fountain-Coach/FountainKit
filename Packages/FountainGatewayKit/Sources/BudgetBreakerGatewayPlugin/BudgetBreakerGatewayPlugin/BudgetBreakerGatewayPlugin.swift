import Foundation
import FountainRuntime

/// Plugin providing budget checks and health endpoints.
public struct BudgetBreakerGatewayPlugin: Sendable {
    public let router: Router
    public init() {
        self.router = Router()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
