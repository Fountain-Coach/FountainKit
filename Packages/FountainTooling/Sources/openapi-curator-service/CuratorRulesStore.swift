import Foundation
import OpenAPICurator
import Yams

/// Actor-backed store for curator rules with optional config reloading.
public actor CuratorRulesStore {
    public private(set) var rules: Rules
    private let configURL: URL?

    public init(initialRules: Rules, configURL: URL?) {
        self.rules = initialRules
        self.configURL = configURL
    }

    public var configPath: URL? { configURL }

    /// Reload rules from the configured URL if available.
    /// Returns true when reload applied.
    @discardableResult
    public func reload() async -> Bool {
        guard let url = configURL else { return false }
        guard let contents = try? String(contentsOf: url) else { return false }
        self.rules = parseRules(from: contents)
        return true
    }

    /// Replace rules with a new YAML string and persist to disk.
    @discardableResult
    public func replace(with yaml: String) async -> Bool {
        guard let url = configURL else { return false }
        do {
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            self.rules = parseRules(from: yaml)
            return true
        } catch {
            return false
        }
    }
}

/// Parses curator rules from a YAML string.
public func parseRules(from yaml: String) -> Rules {
    if let obj = try? Yams.load(yaml: yaml) as? [String: Any] {
        let renames = obj["renames"] as? [String: String] ?? [:]
        return Rules(renames: renames)
    }
    return Rules()
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
