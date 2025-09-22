import Foundation
import FountainStoreClient
import FountainRuntime

public struct UserObjectiveRequest: Codable, Sendable {
    public let objective: String
    public init(objective: String) { self.objective = objective }
}

public struct FunctionCall: Codable, Sendable {
    public let name: String
    public let arguments: [String: String]
    public init(name: String, arguments: [String: String]) { self.name = name; self.arguments = arguments }
}

public struct PlanResponse: Codable, Sendable {
    public let objective: String
    public let steps: [FunctionCall]
    public init(objective: String, steps: [FunctionCall]) { self.objective = objective; self.steps = steps }
}

public struct PlanExecutionRequest: Codable, Sendable {
    public let objective: String
    public let steps: [FunctionCall]
    public init(objective: String, steps: [FunctionCall]) { self.objective = objective; self.steps = steps }
}

public struct FunctionCallResult: Codable, Sendable {
    public let step: String
    public let arguments: [String: String]
    public let output: String
    public init(step: String, arguments: [String: String], output: String) {
        self.step = step; self.arguments = arguments; self.output = output
    }
}

public struct ExecutionResult: Codable, Sendable {
    public let results: [FunctionCallResult]
    public init(results: [FunctionCallResult]) { self.results = results }
}

public struct ChatReflectionRequest: Codable, Sendable {
    public let corpusId: String
    public let message: String
    public init(corpusId: String, message: String) { self.corpusId = corpusId; self.message = message }
    enum CodingKeys: String, CodingKey { case corpusId = "corpus_id"; case message }
}

public struct ReflectionItem: Codable, Sendable {
    public let timestamp: String
    public let content: String
    public init(timestamp: String, content: String) { self.timestamp = timestamp; self.content = content }
}

public struct HistoryListResponse: Codable, Sendable {
    public let reflections: [ReflectionItem]
    public init(reflections: [ReflectionItem]) { self.reflections = reflections }
}

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let body: Data
    public init(method: String, path: String, body: Data = Data()) {
        self.method = method; self.path = path; self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
}

public final class PlannerRouter: @unchecked Sendable {
    let persistence: FountainStoreClient
    public init(persistence: FountainStoreClient) { self.persistence = persistence }

    // MARK: - Operation Handlers

    /// `POST /planner/reason`
    public func planner_reason(_ input: UserObjectiveRequest) async throws -> HTTPResponse {
        let plan = PlanResponse(objective: input.objective, steps: [])
        let data = try JSONEncoder().encode(plan)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `POST /planner/execute`
    public func planner_execute(_ input: PlanExecutionRequest) async throws -> HTTPResponse {
        let results = input.steps.map { FunctionCallResult(step: $0.name, arguments: $0.arguments, output: "ok") }
        let data = try JSONEncoder().encode(ExecutionResult(results: results))
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `GET /planner/corpora`
    public func planner_list_corpora() async throws -> HTTPResponse {
        let (_, corpora) = try await persistence.listCorpora()
        let data = try JSONEncoder().encode(corpora)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `GET /planner/reflections/{corpus_id}`
    public func get_reflection_history(corpusId: String) async throws -> HTTPResponse {
        let (_, refs) = try await persistence.listReflections(corpusId: corpusId)
        let items = refs.map { ReflectionItem(timestamp: String($0.ts), content: $0.content) }
        let data = try JSONEncoder().encode(HistoryListResponse(reflections: items))
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `GET /planner/reflections/{corpus_id}/semantic-arc`
    public func get_semantic_arc(corpusId: String) async throws -> HTTPResponse {
        let (_, refs) = try await persistence.listReflections(corpusId: corpusId)
        let obj: [String: Any] = ["corpus_id": corpusId, "total": refs.count]
        let data = try JSONSerialization.data(withJSONObject: obj)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `POST /planner/reflections`
    public func post_reflection(_ input: ChatReflectionRequest) async throws -> HTTPResponse {
        let reflection = Reflection(corpusId: input.corpusId, reflectionId: UUID().uuidString, question: input.message, content: input.message)
        _ = try await persistence.addReflection(reflection)
        let item = ReflectionItem(timestamp: String(reflection.ts), content: reflection.content)
        let data = try JSONEncoder().encode(item)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `GET /metrics`
    public func metrics_metrics_get() async throws -> HTTPResponse {
        let body = Data("planner_requests_total 0\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let pathOnly = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? request.path
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: true)
        switch request.method {
        case "POST":
            if segments.count == 2 && segments[0] == "planner" && segments[1] == "reason" {
                guard let obj = try? JSONDecoder().decode(UserObjectiveRequest.self, from: request.body) else {
                    return HTTPResponse(status: 422)
                }
                return try await planner_reason(obj)
            }
            if segments.count == 2 && segments[0] == "planner" && segments[1] == "execute" {
                guard let obj = try? JSONDecoder().decode(PlanExecutionRequest.self, from: request.body) else {
                    return HTTPResponse(status: 422)
                }
                return try await planner_execute(obj)
            }
            if segments.count == 2 && segments[0] == "planner" && segments[1] == "reflections" {
                guard let incoming = try? JSONDecoder().decode(ChatReflectionRequest.self, from: request.body) else {
                    return HTTPResponse(status: 422)
                }
                return try await post_reflection(incoming)
            }
            return HTTPResponse(status: 404)
        case "GET":
            if segments.count == 2 && segments[0] == "planner" && segments[1] == "corpora" {
                return try await planner_list_corpora()
            }
            if segments.count == 3 && segments[0] == "planner" && segments[1] == "reflections" {
                let corpusId = String(segments[2])
                return try await get_reflection_history(corpusId: corpusId)
            }
            if segments.count == 4 && segments[0] == "planner" && segments[1] == "reflections" && segments[3] == "semantic-arc" {
                let corpusId = String(segments[2])
                return try await get_semantic_arc(corpusId: corpusId)
            }
            if segments.count == 1 && segments[0] == "metrics" {
                return try await metrics_metrics_get()
            }
            return HTTPResponse(status: 404)
        default:
            return HTTPResponse(status: 404)
        }
    }
}

public func makePlannerKernel(service svc: FountainStoreClient) -> HTTPKernel {
    let router = PlannerRouter(persistence: svc)
    return HTTPKernel { req in
        let ar = HTTPRequest(method: req.method, path: req.path, body: req.body)
        let resp = try await router.route(ar)
        return FountainRuntime.HTTPResponse(status: resp.status, headers: resp.headers, body: resp.body)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
