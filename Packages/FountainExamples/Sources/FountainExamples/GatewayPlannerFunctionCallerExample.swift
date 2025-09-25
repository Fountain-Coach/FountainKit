import Foundation
import FountainRuntime
import FountainStoreClient
import GatewayPersonaOrchestrator
import PlannerService
import FunctionCallerService

/// Demonstrates how gateway personas, the planner service, and the function
/// caller service collaborate when orchestrating a user objective.
public struct GatewayPlannerFunctionCallerExample: Sendable {
    public struct Outcome: Sendable {
        public let plan: PlanResponse
        public let functions: FunctionsListResponse
        public let execution: ExecutionResult
    }

    private let store: FountainStoreClient
    private let planner: PlannerRouter
    private let functionCaller: FunctionCallerRouter
    private let orchestrator: GatewayPersonaOrchestrator
    private let corpusId: String

    public init(corpusId: String = "demo") {
        let embedded = EmbeddedFountainStoreClient()
        self.store = FountainStoreClient(client: embedded)
        self.planner = PlannerRouter(persistence: store)
        self.functionCaller = FunctionCallerRouter(persistence: store)
        self.orchestrator = GatewayPersonaOrchestrator(personas: [
            PathAllowPersona(name: "PlannerPersona", allowed: ["POST /planner/reason", "POST /planner/execute"]),
            PathAllowPersona(name: "FunctionCatalogPersona", allowed: ["GET /functions"])
        ])
        self.corpusId = corpusId
    }

    /// Seeds the embedded persistence layer with a demo corpus and function.
    @discardableResult
    public func seedDemoData(functionId: String = "hello-teatro") async throws -> FunctionModel {
        _ = try await store.createCorpus(corpusId)
        let demoFunction = FunctionModel(
            corpusId: corpusId,
            functionId: functionId,
            name: "HelloTeatro",
            description: "Renders a hello world Teatro scene",
            httpMethod: "POST",
            httpPath: "https://example.invalid/teatro"
        )
        _ = try await store.addFunction(demoFunction)
        return demoFunction
    }

    /// Seeds an example function compatible with LocalAgent function-calling docs.
    /// This does not affect existing tests; invoke from demos as needed.
    @discardableResult
    public func seedScheduleMeetingFunction() async throws -> FunctionModel {
        _ = try await store.createCorpus(corpusId)
        let fn = FunctionModel(
            corpusId: corpusId,
            functionId: "schedule_meeting",
            name: "schedule_meeting",
            description: "Schedule a meeting",
            httpMethod: "POST",
            httpPath: "/schedule_meeting"
        )
        _ = try await store.addFunction(fn)
        return fn
    }

    /// Runs the end-to-end demo flow by consulting the gateway and then calling
    /// into the planner and function caller services.
    public func runDemoFlow(objective: String) async throws -> Outcome {
        try await ensureGatewayAllows(method: "POST", path: "/planner/reason")
        let planResponse = try await planner.planner_reason(UserObjectiveRequest(objective: objective))
        let plan = try decode(PlanResponse.self, from: planResponse.body)

        try await ensureGatewayAllows(method: "GET", path: "/functions")
        let listResponse = try await functionCaller.list_functions(page: 1, page_size: 20)
        let functions = try JSONDecoder().decode(FunctionsListResponse.self, from: listResponse.body)

        try await ensureGatewayAllows(method: "POST", path: "/planner/execute")
        let execution = try await executeFirstFunction(from: functions, objective: plan.objective)

        return Outcome(plan: plan, functions: functions, execution: execution)
    }

    private func executeFirstFunction(from list: FunctionsListResponse, objective: String) async throws -> ExecutionResult {
        guard let first = list.functions.first else {
            return ExecutionResult(results: [])
        }
        let step = FunctionCall(name: first.name, arguments: ["function_id": first.function_id])
        let request = PlanExecutionRequest(objective: objective, steps: [step])
        let response = try await planner.planner_execute(request)
        return try decode(ExecutionResult.self, from: response.body)
    }

    private func ensureGatewayAllows(method: String, path: String) async throws {
        let request = FountainRuntime.HTTPRequest(method: method, path: path)
        let verdict = await orchestrator.decide(for: request)
        if case .allow = verdict { return }
        throw ExampleError.denied(verdict)
    }

    private func decode<T: Decodable>(_ type: T.Type = T.self, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ExampleError.decodingFailed(type: T.self, underlying: error)
        }
    }
}

private struct PathAllowPersona: GatewayPersona {
    let name: String
    let allowed: Set<String>

    init(name: String, allowed: [String]) {
        self.name = name
        self.allowed = Set(allowed)
    }

    func evaluate(_ request: FountainRuntime.HTTPRequest) async -> GatewayPersonaVerdict {
        let key = "\(request.method) \(request.path)"
        if allowed.contains(key) {
            return .allow
        }
        if matchesNamespace(of: request.path) {
            return .escalate(reason: "path not permitted", persona: name)
        }
        return .allow
    }

    private func matchesNamespace(of path: String) -> Bool {
        guard let requestRoot = path.split(separator: "/", omittingEmptySubsequences: true).first else {
            return false
        }
        for entry in allowed {
            guard let permittedPath = entry.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).last else {
                continue
            }
            if let allowedRoot = permittedPath.split(separator: "/", omittingEmptySubsequences: true).first,
               allowedRoot == requestRoot {
                return true
            }
        }
        return false
    }
}

public enum ExampleError: Error, CustomStringConvertible, Sendable {
    case denied(GatewayPersonaVerdict)
    case decodingFailed(type: Any.Type, underlying: Error)

    public var description: String {
        switch self {
        case .denied(let verdict):
            return "gateway denied request: \(verdict)"
        case .decodingFailed(let type, let underlying):
            return "failed to decode \(type): \(underlying)"
        }
    }
}
