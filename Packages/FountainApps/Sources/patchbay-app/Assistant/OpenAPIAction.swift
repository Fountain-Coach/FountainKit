import Foundation
import ApiClientsCore

struct OpenAPIAction: Codable, Equatable {
    var service: String
    var operationId: String
    var pathParams: [String: String]? = nil
    var query: [String: String]? = nil
    var body: JSONValue? = nil
}

enum OpenAPIActionParser {
    static func parse(from fn: JSONValue?) -> [OpenAPIAction] {
        guard case .object(let obj)? = fn,
              case .string(let name)? = obj["name"], name == "openapi_action" else { return [] }
        if let args = obj["arguments"], let parsed = parseArguments(args) { return parsed }
        return []
    }

    private static func parseArguments(_ value: JSONValue) -> [OpenAPIAction]? {
        switch value {
        case .object:
            if let action = decode(OpenAPIAction.self, from: value) { return [action] }
        case .array(let arr):
            var actions: [OpenAPIAction] = []
            for el in arr {
                if let a = decode(OpenAPIAction.self, from: el) { actions.append(a) }
            }
            if !actions.isEmpty { return actions }
        default: break
        }
        return nil
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) -> T? {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(T.self, from: data)
        } catch { return nil }
    }

    static func parse(fromText text: String) -> [OpenAPIAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try direct decode (object or array)
        if let data = trimmed.data(using: .utf8) {
            if let obj = try? JSONDecoder().decode(OpenAPIAction.self, from: data) { return [obj] }
            if let arr = try? JSONDecoder().decode([OpenAPIAction].self, from: data) { return arr }
        }
        // Try fenced code block ```json ... ```
        if let range = trimmed.range(of: "```json") ?? trimmed.range(of: "```") {
            let rest = trimmed[range.upperBound...]
            if let end = rest.range(of: "```") {
                let json = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = json.data(using: .utf8) {
                    if let obj = try? JSONDecoder().decode(OpenAPIAction.self, from: data) { return [obj] }
                    if let arr = try? JSONDecoder().decode([OpenAPIAction].self, from: data) { return arr }
                }
            }
        }
        // Heuristic: extract first {...}
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            let json = String(trimmed[start...end])
            if let data = json.data(using: .utf8) {
                if let obj = try? JSONDecoder().decode(OpenAPIAction.self, from: data) { return [obj] }
                if let arr = try? JSONDecoder().decode([OpenAPIAction].self, from: data) { return arr }
            }
        }
        return []
    }
}
