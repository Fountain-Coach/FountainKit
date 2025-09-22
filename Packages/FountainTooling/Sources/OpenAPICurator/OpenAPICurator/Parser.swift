import Foundation

enum Parser {
    static func parse(_ specs: [Spec]) -> OpenAPI {
        let ops = specs.flatMap { $0.operations }
        let exts = specs.reduce(into: [String: [String: String]]()) { result, spec in
            for (op, ext) in spec.extensions {
                result[op, default: [:]].merge(ext) { current, _ in current }
            }
        }
        return OpenAPI(operations: ops, extensions: exts)
    }
}
