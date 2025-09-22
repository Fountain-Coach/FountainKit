import Foundation

/// Request body for token validation.
public struct ValidateRequest: Codable {
    public let token: String
    public init(token: String) { self.token = token }
}

/// Response returned when validating a token.
public struct ValidationResponse: Codable {
    public let valid: Bool
    public let role: String?
    public init(valid: Bool, role: String? = nil) {
        self.valid = valid
        self.role = role
    }
}

/// Response containing claims for a token.
public struct ClaimsResponse: Codable {
    public let role: String?
    public let scopes: [String]
    public init(role: String? = nil, scopes: [String]) {
        self.role = role
        self.scopes = scopes
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
