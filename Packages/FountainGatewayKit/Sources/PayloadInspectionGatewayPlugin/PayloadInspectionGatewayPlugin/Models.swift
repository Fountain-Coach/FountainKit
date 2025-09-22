import Foundation

/// Request model for payload inspection.
public struct PayloadInspectionRequest: Codable, Sendable {
    public let payload: String
    public init(payload: String) { self.payload = payload }
}

/// Response model from payload inspection.
public struct PayloadInspectionResponse: Codable, Sendable {
    public let sanitized: String
    public let violations: [String]
    public init(sanitized: String, violations: [String]) {
        self.sanitized = sanitized
        self.violations = violations
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
