import Foundation

public struct Spec {
    public let operations: [String]
    public let extensions: [String: [String: String]]
    public init(operations: [String], extensions: [String: [String: String]] = [:]) {
        self.operations = operations
        self.extensions = extensions
    }
}

public struct OpenAPI {
    public var operations: [String]
    public var extensions: [String: [String: String]]
    public init(operations: [String], extensions: [String: [String: String]] = [:]) {
        self.operations = operations
        self.extensions = extensions
    }
}

public struct Truth: Codable, Equatable {
    public let visibility: String
    public let allowAsTool: Bool
    public let reason: String
    public init(visibility: String, allowAsTool: Bool, reason: String) {
        self.visibility = visibility
        self.allowAsTool = allowAsTool
        self.reason = reason
    }
}

public struct Rules: Sendable {
    public let renames: [String: String]
    public let allowlist: [String]
    public let denylist: [String]
    public init(renames: [String: String] = [:], allowlist: [String] = [], denylist: [String] = []) {
        self.renames = renames
        self.allowlist = allowlist
        self.denylist = denylist
    }
}

public struct CuratorReport {
    public let appliedRules: [String]
    public let collisions: [String]
    public let diff: [String]
    public let truthTable: [String: Truth]
    public init(appliedRules: [String], collisions: [String], diff: [String], truthTable: [String: Truth]) {
        self.appliedRules = appliedRules
        self.collisions = collisions
        self.diff = diff
        self.truthTable = truthTable
    }
}

public func curate(specs: [Spec], rules: Rules) -> (spec: OpenAPI, report: CuratorReport) {
    let parsed = Parser.parse(specs)
    let normalized = Resolver.normalize(parsed)
    let (ruled, applied, truth) = RulesEngine.apply(rules, to: normalized)
    let diff = normalized.operations.filter { !ruled.operations.contains($0) }
    let (deduped, collisions) = CollisionResolver.resolve(ruled)
    let report = ReportBuilder.build(appliedRules: applied, collisions: collisions, diff: diff, truthTable: truth)
    return (deduped, report)
}
