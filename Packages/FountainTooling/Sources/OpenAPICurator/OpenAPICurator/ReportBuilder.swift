import Foundation

enum ReportBuilder {
    static func build(appliedRules: [String], collisions: [String], diff: [String], truthTable: [String: Truth]) -> CuratorReport {
        CuratorReport(appliedRules: appliedRules, collisions: collisions, diff: diff, truthTable: truthTable)
    }
}
