import Foundation

/// Factory that provides the Security Sentinel client.
public enum SentinelClientFactory {
    /// Closure producing ``SecuritySentinelClient`` instances.
    ///
    /// Tests and integrators may override this to supply mock clients.
    nonisolated(unsafe) public static var make: () -> SecuritySentinelClient = {
        let env = ProcessInfo.processInfo.environment
        let enabled = (env["SEC_SENTINEL_ENABLED"] ?? "true").lowercased() != "false"
        let hasURL = env["SEC_SENTINEL_URL"]?.isEmpty == false
        let hasKey = env["SEC_SENTINEL_API_KEY"]?.isEmpty == false
        if enabled && hasURL && hasKey {
            return LLMSecuritySentinelClient()
        }
        return NoopSecuritySentinelClient()
    }
}

/// Fallback client used when the Security Sentinel is disabled or not configured.
struct NoopSecuritySentinelClient: SecuritySentinelClient {
    func consult(summary: String, context: [String : (any Codable & Sendable)]?) async throws -> SentinelDecision {
        let ts = ISO8601DateFormatter().string(from: Date())
        return SentinelDecision(
            decision: .allow,
            reason: "sentinel disabled",
            confidence: nil,
            model: nil,
            requestID: UUID().uuidString,
            latencyMS: 0,
            source: .fallback_rules,
            timestamp: ts
        )
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
