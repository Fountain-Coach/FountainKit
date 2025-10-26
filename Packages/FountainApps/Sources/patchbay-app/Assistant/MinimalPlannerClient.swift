import Foundation

struct PlannerFunctionCall: Codable {
    var name: String
    var arguments: [String: AnyCodable]
}

struct PlannerPlanResponse: Codable {
    var objective: String?
    var steps: [PlannerFunctionCall]?
}

struct PlannerPlanExecutionRequest: Codable {
    var objective: String
    var steps: [PlannerFunctionCall]
}

struct PlannerExecutionResult: Codable {
    var step: String?
    var arguments: [String: AnyCodable]?
    var output: AnyCodable?
}

enum MinimalPlannerClientError: Error { case badURL; case http(Int); case decode }

struct MinimalPlannerClient {
    let baseURL: URL
    let session: URLSession = .shared

    @MainActor
    func reason(objective: String) async throws -> PlannerPlanResponse {
        let url = baseURL.appendingPathComponent("/planner/reason")
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["objective": objective]
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MinimalPlannerClientError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw MinimalPlannerClientError.http(http.statusCode) }
        return try JSONDecoder().decode(PlannerPlanResponse.self, from: data)
    }

    @MainActor
    func execute(_ request: PlannerPlanExecutionRequest) async throws -> [PlannerExecutionResult] {
        let url = baseURL.appendingPathComponent("/planner/execute")
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MinimalPlannerClientError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw MinimalPlannerClientError.http(http.statusCode) }
        // ExecutionResult in spec is an object; we accept array or object for flexibility
        if let arr = try? JSONDecoder().decode([PlannerExecutionResult].self, from: data) { return arr }
        if let one = try? JSONDecoder().decode(PlannerExecutionResult.self, from: data) { return [one] }
        return []
    }
}

// Lightweight AnyCodable to carry planner arguments
struct AnyCodable: Codable {
    let value: Any?
    init(_ value: Any?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = nil; return }
        if let b = try? container.decode(Bool.self) { value = b; return }
        if let i = try? container.decode(Int.self) { value = i; return }
        if let d = try? container.decode(Double.self) { value = d; return }
        if let s = try? container.decode(String.self) { value = s; return }
        if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value as Any }; return }
        if let arr = try? container.decode([AnyCodable].self) { value = arr.map { $0.value as Any }; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case nil:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        case let dict as [String: Any]:
            let mapped = dict.mapValues { AnyCodable($0) }
            try container.encode(mapped)
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported JSON value")
            throw EncodingError.invalidValue(value as Any, context)
        }
    }
}
