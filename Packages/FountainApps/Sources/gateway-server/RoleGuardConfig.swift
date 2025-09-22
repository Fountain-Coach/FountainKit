import Foundation
import Yams
import FountainStoreClient

/// Loads role guard rules from FountainStore's `config/roleguard.yml`.
/// Falls back to a local file when FountainStore is unavailable.
public func loadRoleGuardRules(store: ConfigurationStore? = nil,
                               path: URL? = nil,
                               environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: RoleRequirement] {
    let svc = store ?? ConfigurationStore.fromEnvironment(environment)
    if let data = svc?.getSync("roleguard.yml"), let text = String(data: data, encoding: .utf8) {
        return parseRoleGuardRules(from: text)
    }
    let filePath = path?.path ?? (environment["ROLE_GUARD_PATH"] ?? "Configuration/roleguard.yml")
    guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [:] }
    return parseRoleGuardRules(from: text)
}

private func parseRoleGuardRules(from text: String) -> [String: RoleRequirement] {
    do {
        if let yaml = try Yams.load(yaml: text) as? [String: Any], let rawRules = yaml["rules"] as? [String: Any] {
            var result: [String: RoleRequirement] = [:]
            for (prefix, val) in rawRules {
                if let s = val as? String {
                    result[prefix] = RoleRequirement(roles: [s])
                } else if let arr = val as? [String] {
                    result[prefix] = RoleRequirement(roles: arr)
                } else if let dict = val as? [String: Any] {
                    let roles = dict["roles"] as? [String]
                    let scopes = dict["scopes"] as? [String]
                    result[prefix] = RoleRequirement(roles: roles, scopes: scopes, requireAllScopes: ( (dict["scopes_mode"] as? String)?.lowercased() == "all" ) || (dict["require_all_scopes"] as? Bool ?? false), methods: (dict["methods"] as? [String])?.map { $0.uppercased() }, deny: dict["deny"] as? Bool ?? false)
                }
            }
            return result
        }
    } catch {
        // ignore parse errors
    }
    return [:]
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
