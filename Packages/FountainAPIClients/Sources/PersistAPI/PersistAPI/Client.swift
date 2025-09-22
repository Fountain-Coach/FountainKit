import Foundation
import ApiClientsCore

public struct PersistCapabilities: Codable, Sendable, Equatable {
    public var corpus: Bool?
    public var documents: [String]?
    public var query: [String]?
    public var transactions: [String]?
    public var admin: [String]?
    public var experimental: [String]?
}

public struct ListCorporaResponse: Codable, Sendable, Equatable {
    public var total: Int
    public var corpora: [String]
}

public struct CorpusCreateRequest: Codable, Sendable, Equatable {
    public var corpusId: String
    public init(corpusId: String) { self.corpusId = corpusId }
}

public struct CorpusResponse: Codable, Sendable, Equatable {
    public var corpusId: String
    public var message: String?
}

public struct Baseline: Codable, Sendable, Equatable {
    public var baselineId: String
    public var corpusId: String
    public var content: String
    public init(baselineId: String, corpusId: String, content: String) {
        self.baselineId = baselineId
        self.corpusId = corpusId
        self.content = content
    }
}

public struct Reflection: Codable, Sendable, Equatable {
    public var reflectionId: String
    public var corpusId: String
    public var question: String
    public var content: String
    public init(reflectionId: String, corpusId: String, question: String, content: String) {
        self.reflectionId = reflectionId
        self.corpusId = corpusId
        self.question = question
        self.content = content
    }
}

public struct SuccessResponse: Codable, Sendable, Equatable {
    public var message: String
}

public struct FunctionModel: Codable, Sendable, Equatable {
    public var functionId: String
    public var corpusId: String
    public var name: String
    public var description: String
    public var httpMethod: String
    public var httpPath: String
}

public struct ListFunctionsResponse: Codable, Sendable, Equatable {
    public var total: Int
    public var functions: [FunctionModel]
}

public actor PersistClient {
    private let http: RESTClient

    public init(baseURL: URL, apiKey: String? = nil) {
        var headers: [String: String] = ["Accept": "application/json"]
        if let apiKey = apiKey { headers["X-API-Key"] = apiKey }
        self.http = RESTClient(baseURL: baseURL, defaultHeaders: headers)
    }

    // GET /capabilities
    public func capabilities() async throws -> PersistCapabilities {
        guard let url = http.buildURL(path: "/capabilities") else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(PersistCapabilities.self, from: resp.data)
    }

    // GET /corpora
    public func listCorpora(limit: Int = 50, offset: Int = 0) async throws -> ListCorporaResponse {
        let query: [String: String?] = ["limit": String(limit), "offset": String(offset)]
        guard let url = http.buildURL(path: "/corpora", query: query) else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(ListCorporaResponse.self, from: resp.data)
    }

    // POST /corpora
    public func createCorpus(_ req: CorpusCreateRequest) async throws -> CorpusResponse {
        guard let url = http.buildURL(path: "/corpora") else { throw APIError.invalidURL }
        let body = try JSONEncoder().encode(req)
        let resp = try await http.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
        return try JSONDecoder().decode(CorpusResponse.self, from: resp.data)
    }

    // POST /corpora/{corpusId}/reflections
    public func addReflection(corpusId: String, reflection: Reflection) async throws -> SuccessResponse {
        guard let url = http.buildURL(path: "/corpora/\(corpusId)/reflections") else { throw APIError.invalidURL }
        let body = try JSONEncoder().encode(reflection)
        let req = APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body)
        let resp = try await http.send(req)
        return try JSONDecoder().decode(SuccessResponse.self, from: resp.data)
    }

    // GET /corpora/{corpusId}/reflections
    public func listReflections(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, reflections: [Reflection]) {
        let q: [String: String?] = ["limit": String(limit), "offset": String(offset)]
        guard let url = http.buildURL(path: "/corpora/\(corpusId)/reflections", query: q) else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        let obj = try JSONDecoder().decode([String: JSONValue].self, from: resp.data)
        let total = (obj["total"]?.number).flatMap { Int($0) } ?? 0
        let list = (obj["reflections"]?.array ?? []).compactMap { item -> Reflection? in
            guard case let .object(o) = item else { return nil }
            return try? JSONSerialization.data(withJSONObject: o.mapValues { $0.toAny() }, options: []).decode(Reflection.self)
        }
        return (total, list)
    }

    // POST /corpora/{corpusId}/baselines
    public func addBaseline(corpusId: String, baseline: Baseline) async throws -> SuccessResponse {
        guard let url = http.buildURL(path: "/corpora/\(corpusId)/baselines") else { throw APIError.invalidURL }
        let body = try JSONEncoder().encode(baseline)
        let resp = try await http.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
        return try JSONDecoder().decode(SuccessResponse.self, from: resp.data)
    }

    // GET /functions
    public func listFunctions(limit: Int = 50, offset: Int = 0, q: String? = nil) async throws -> ListFunctionsResponse {
        var query: [String: String?] = ["limit": String(limit), "offset": String(offset)]
        if let q = q { query["q"] = q }
        guard let url = http.buildURL(path: "/functions", query: query) else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(ListFunctionsResponse.self, from: resp.data)
    }

    // GET /functions/{functionId}
    public func getFunctionDetails(functionId: String) async throws -> FunctionModel? {
        guard let url = http.buildURL(path: "/functions/\(functionId)") else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(FunctionModel.self, from: resp.data)
    }
}

private extension JSONValue {
    var number: Double? { if case let .number(n) = self { return n } else { return nil } }
    var array: [JSONValue]? { if case let .array(a) = self { return a } else { return nil } }
    func toAny() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues { $0.toAny() }
        case .array(let a): return a.map { $0.toAny() }
        case .null: return NSNull()
        }
    }
}

private extension Data {
    func decode<T: Decodable>(_ t: T.Type = T.self) throws -> T { try JSONDecoder().decode(T.self, from: self) }
}
