import Foundation

public actor RoleGuardMetrics {
    public static let shared = RoleGuardMetrics()

    private var unauthorized = 0
    private var forbidden = 0
    private var reloads = 0
    private var activeRules = 0

    public func recordUnauthorized() { unauthorized += 1 }
    public func recordForbidden() { forbidden += 1 }
    public func recordReload(ruleCount: Int) { reloads += 1; activeRules = ruleCount }
    public func setActiveRules(_ count: Int) { activeRules = count }

    public func snapshot() -> [String: Int] {
        return [
            "roleguard_unauthorized_total": unauthorized,
            "roleguard_forbidden_total": forbidden,
            "roleguard_reloads_total": reloads,
            "roleguard_active_rules": activeRules
        ]
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

