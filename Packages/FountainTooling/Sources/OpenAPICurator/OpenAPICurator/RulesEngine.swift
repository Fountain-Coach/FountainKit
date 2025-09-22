import Foundation

enum RulesEngine {
    static func apply(_ rules: Rules, to api: OpenAPI) -> (OpenAPI, [String], [String: Truth]) {
        var operations = api.operations
        var exts = api.extensions
        var applied: [String] = []
        var truth: [String: Truth] = [:]
        for (index, op) in operations.enumerated() {
            if let newName = rules.renames[op] {
                operations[index] = newName
                if let ext = exts.removeValue(forKey: op) { exts[newName] = ext }
                applied.append("\(op)->\(newName)")
            }
            if let opExts = exts[operations[index]] {
                let vis = opExts["x-fountain.visibility"] ?? ""
                let reason = opExts["x-fountain.reason"] ?? ""
                let allow = (opExts["x-fountain.allow-as-tool"]?.lowercased() == "true")
                truth[operations[index]] = Truth(visibility: vis, allowAsTool: allow, reason: reason)
                for (key, value) in opExts where key.hasPrefix("x-fountain.") {
                    applied.append("\(key)=\(value)")
                }
            }
        }
        if !rules.allowlist.isEmpty {
            let allowed = Set(rules.allowlist)
            operations = operations.filter { allowed.contains($0) }
        }
        if !rules.denylist.isEmpty {
            let denied = Set(rules.denylist)
            let removed = operations.filter { denied.contains($0) }
            applied.append(contentsOf: removed.map { "deny:\($0)" })
            operations = operations.filter { !denied.contains($0) }
        }
        return (OpenAPI(operations: operations, extensions: exts), applied, truth)
    }
}
