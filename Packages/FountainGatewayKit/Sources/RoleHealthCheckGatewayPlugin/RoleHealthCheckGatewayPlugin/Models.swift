import Foundation

/// Request model for role health-check operations.
public struct RoleHealthCheckRequest: Codable, Sendable {
    public let corpusId: String
    public let roleName: String
    public init(corpusId: String, roleName: String) {
        self.corpusId = corpusId
        self.roleName = roleName
    }
}

/// Represents a role's basic information.
public struct RoleInfo: Codable, Sendable {
    public let name: String
    public let prompt: String
    public init(name: String, prompt: String) {
        self.name = name
        self.prompt = prompt
    }
}

/// Placeholder empty body.
public struct NoBody: Codable, Sendable {}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
