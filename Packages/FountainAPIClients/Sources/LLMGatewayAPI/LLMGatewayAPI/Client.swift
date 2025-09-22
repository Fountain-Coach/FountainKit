import Foundation
import ApiClientsCore

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}
public struct ChatFunction: Codable, Sendable, Equatable { public var name: String; public var description: String? }
public struct ChatFunctionCall: Codable, Sendable, Equatable { public var name: String }

public struct ChatRequest: Codable, Sendable, Equatable {
    public var model: String
    public var messages: [ChatMessage]
    public var functions: [ChatFunction]?
    public var function_call: Either<String, ChatFunctionCall>?

    public init(model: String, messages: [ChatMessage], functions: [ChatFunction]? = nil, function_call: Either<String, ChatFunctionCall>? = nil) {
        self.model = model
        self.messages = messages
        self.functions = functions
        self.function_call = function_call
    }
}

public enum Either<A: Codable & Sendable & Equatable, B: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    case left(A)
    case right(B)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let a = try? container.decode(A.self) { self = .left(a); return }
        if let b = try? container.decode(B.self) { self = .right(b); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Could not decode Either")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .left(let a): try container.encode(a)
        case .right(let b): try container.encode(b)
        }
    }
}

public actor LLMGatewayClient {
    private let http: RESTClient

    public init(baseURL: URL, bearerToken: String? = nil) {
        var headers: [String: String] = ["Accept": "application/json"]
        if let token = bearerToken { headers["Authorization"] = "Bearer \(token)" }
        self.http = RESTClient(baseURL: baseURL, defaultHeaders: headers)
    }

    // POST /chat
    public func chat(_ req: ChatRequest) async throws -> JSONValue {
        guard let url = http.buildURL(path: "/chat") else { throw APIError.invalidURL }
        let body = try JSONEncoder().encode(req)
        let resp = try await http.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
        return try JSONDecoder().decode(JSONValue.self, from: resp.data)
    }

    // GET /metrics
    public func metrics() async throws -> JSONValue {
        guard let url = http.buildURL(path: "/metrics") else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(JSONValue.self, from: resp.data)
    }
}
