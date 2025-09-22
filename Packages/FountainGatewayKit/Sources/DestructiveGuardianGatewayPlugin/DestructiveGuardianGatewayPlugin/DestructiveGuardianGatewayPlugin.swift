import Foundation
import FountainRuntime

/// Plugin that evaluates destructive requests via an HTTP endpoint.
public struct DestructiveGuardianGatewayPlugin: Sendable {
    public let router: Router
    private let handlers: Handlers

    public init(sensitivePaths: [String] = ["/"],
                privilegedTokens: [String] = [],
                auditURL: URL = URL(fileURLWithPath: "logs/guardian.log")) {
        let h = Handlers(sensitivePaths: sensitivePaths,
                         privilegedTokens: Set(privilegedTokens),
                         auditURL: auditURL)
        self.handlers = h
        self.router = Router(handlers: h)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
