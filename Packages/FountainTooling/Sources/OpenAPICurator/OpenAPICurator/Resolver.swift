import Foundation

enum Resolver {
    static func normalize(_ api: OpenAPI) -> OpenAPI {
        let normalized = api.operations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return OpenAPI(operations: normalized, extensions: api.extensions)
    }
}
