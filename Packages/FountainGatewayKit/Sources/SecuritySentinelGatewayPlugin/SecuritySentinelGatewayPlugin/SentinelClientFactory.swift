import Foundation

/// Factory that provides the Security Sentinel client.
public enum SentinelClientFactory {
    /// Closure producing ``SecuritySentinelClient`` instances.
    ///
    /// Tests may override this to supply mock clients.
    nonisolated(unsafe) public static var make: () -> SecuritySentinelClient = {
        LLMSecuritySentinelClient()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
