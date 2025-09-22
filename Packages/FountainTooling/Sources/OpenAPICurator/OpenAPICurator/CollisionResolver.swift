import Foundation

enum CollisionResolver {
    static func resolve(_ api: OpenAPI) -> (OpenAPI, [String]) {
        var seen: Set<String> = []
        var collisions: [String] = []
        var result: [String] = []
        var exts = api.extensions
        for name in api.operations {
            var candidate = name
            var counter = 1
            while seen.contains(candidate) {
                collisions.append(name)
                candidate = "\(name)_\(counter)"
                counter += 1
            }
            seen.insert(candidate)
            result.append(candidate)
            if candidate != name, let ext = exts.removeValue(forKey: name) {
                exts[candidate] = ext
            }
        }
        return (OpenAPI(operations: result, extensions: exts), collisions)
    }
}
