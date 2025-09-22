import Foundation

/// Request to check client budget.
public struct BudgetCheckRequest: Codable {
    public let routeId: String
    public let clientId: String
    public let amount: Int
    public init(routeId: String, clientId: String, amount: Int) {
        self.routeId = routeId
        self.clientId = clientId
        self.amount = amount
    }
}

/// Response indicating budget allowance.
public struct BudgetCheckResponse: Codable {
    public let allowed: Bool
    public let remaining: Int
    public init(allowed: Bool, remaining: Int) {
        self.allowed = allowed
        self.remaining = remaining
    }
}

/// Health response for budget plugin.
public struct BudgetHealthResponse: Codable {
    public let status: String
    public init(status: String) { self.status = status }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
