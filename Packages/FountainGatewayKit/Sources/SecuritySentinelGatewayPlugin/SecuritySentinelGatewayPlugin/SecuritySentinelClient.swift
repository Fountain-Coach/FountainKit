import Foundation

/// Abstraction over clients capable of consulting the Security Sentinel service.
public protocol SecuritySentinelClient: Sendable {
    /// Consult the Security Sentinel with a summary and optional context.
    /// - Parameters:
    ///   - summary: Concise description of the proposed action.
    ///   - context: Additional metadata describing the request.
    /// - Returns: A structured decision from the sentinel.
    func consult(summary: String, context: [String: (any Codable & Sendable)]?) async throws -> SentinelDecision
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
