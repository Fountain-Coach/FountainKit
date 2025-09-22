import Foundation

/// Request model for consulting the Security Sentinel.
public struct ConsultRequest: Codable, Sendable {
    /// Summary of the action the user intends to perform.
    public let summary: String
    /// Additional context describing the request.
    public let context: String

    public init(summary: String, context: String) {
        self.summary = summary
        self.context = context
    }

    enum ValidationError: Error {
        case invalidSummary
    }

    /// Validates that the summary is non-empty and no longer than 1000 characters.
    public func validate() throws {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1000 else {
            throw ValidationError.invalidSummary
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🖚️ All rights reserved.
