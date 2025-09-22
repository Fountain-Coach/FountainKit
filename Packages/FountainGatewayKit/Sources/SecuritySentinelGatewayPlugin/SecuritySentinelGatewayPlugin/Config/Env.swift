import Foundation

/// Environment configuration for the LLM Security Sentinel client.
enum SentinelEnv {
    static var enabled: Bool {
        (ProcessInfo.processInfo.environment["SEC_SENTINEL_ENABLED"] ?? "true").lowercased() != "false"
    }
    static var url: String? {
        ProcessInfo.processInfo.environment["SEC_SENTINEL_URL"]
    }
    static var apiKey: String? {
        ProcessInfo.processInfo.environment["SEC_SENTINEL_API_KEY"]
    }
    static var timeoutMS: Int {
        Int(ProcessInfo.processInfo.environment["SEC_SENTINEL_TIMEOUT_MS"] ?? "4000") ?? 4000
    }
    static var retries: Int {
        Int(ProcessInfo.processInfo.environment["SEC_SENTINEL_RETRIES"] ?? "1") ?? 1
    }
    static var model: String? {
        ProcessInfo.processInfo.environment["SEC_SENTINEL_MODEL"]
    }
    static var personaPath: String {
        ProcessInfo.processInfo.environment["SEC_SENTINEL_PERSONA_PATH"] ?? "openapi/personas/security-sentinel.md"
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
