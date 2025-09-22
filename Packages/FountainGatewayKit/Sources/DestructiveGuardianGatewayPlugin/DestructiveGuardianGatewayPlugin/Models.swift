import Foundation

/// Request body for guardian evaluation.
public struct GuardianEvaluateRequest: Codable, Sendable {
    public let method: String
    public let path: String
    public let manualApproval: Bool?
    public let serviceToken: String?

    public init(method: String,
                path: String,
                manualApproval: Bool?,
                serviceToken: String?) {
        self.method = method
        self.path = path
        self.manualApproval = manualApproval
        self.serviceToken = serviceToken
    }
}

/// Response body indicating allow or deny decision.
public struct GuardianEvaluateResponse: Codable, Sendable {
    public let decision: String
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
