import Foundation
import FountainRuntime

/// Routes budget breaker requests to handlers.
public struct Router: Sendable {
    public var handlers: Handlers
    public init(handlers: Handlers = Handlers()) { self.handlers = handlers }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("POST", "/budget/check"):
            let body = try? JSONDecoder().decode(BudgetCheckRequest.self, from: request.body)
            return try await handlers.budgetCheck(request, body: body)
        case ("POST", "/budget/health"):
            return try await handlers.budgetHealth(request, body: nil)
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
