import Foundation

/// Actor-backed store for RoleGuard rules with optional config file reloads.
public actor RoleGuardStore {
    public private(set) var rules: [String: RoleRequirement]
    private let configURL: URL?

    public init(initialRules: [String: RoleRequirement], configURL: URL?) {
        self.rules = initialRules
        self.configURL = configURL
    }

    public var configPath: URL? { configURL }

    /// Reload rules from the configured URL if available.
    /// Returns true when reload applied.
    @discardableResult
    public func reload() async -> Bool {
        guard let url = configURL else { return false }
        let newRules = loadRoleGuardRules(path: url)
        guard !newRules.isEmpty else { return false }
        self.rules = newRules
        return true
    }

    /// Replace rules programmatically.
    public func replace(with newRules: [String: RoleRequirement]) {
        self.rules = newRules
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
