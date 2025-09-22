import Foundation
import FountainRuntime

/// Plugin exposing LLM gateway endpoints.
public struct LLMGatewayPlugin: Sendable {
    public let router: Router

    /// Creates a new plugin instance.
    public init() {
        self.router = Router()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
