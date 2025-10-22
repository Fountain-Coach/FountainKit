import Foundation
import OpenAPIRuntime
import FountainStoreClient
import Foundation

public struct PlannerOpenAPI: APIProtocol, @unchecked Sendable {
    let persistence: FountainStoreClient
    public init(persistence: FountainStoreClient) { self.persistence = persistence }

    public func planner_reason(_ input: Operations.planner_reason.Input) async throws -> Operations.planner_reason.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let objective = req.objective.lowercased()
        func extractArgs(_ s: String) -> [String: String] {
            var out: [String: String] = [:]
            for part in s.split(separator: " ") {
                if let eq = part.firstIndex(of: "=") {
                    let k = String(part[..<eq])
                    let v = String(part[part.index(after: eq)...])
                    out[k] = v
                }
            }
            return out
        }
        let kv = extractArgs(req.objective)
        let id = kv["id"]
        let screenplayId = kv["screenplay"] ?? id
        let notationId = kv["notation"] ?? kv["session"]
        var steps: [Components.Schemas.FunctionCall] = []

        func call(_ name: String, _ args: [String: (any Sendable)?]) {
            if let container = try? OpenAPIObjectContainer(unvalidatedValue: args) {
                steps.append(.init(name: name, arguments: .init(additionalProperties: container)))
            }
        }

        if objective.contains("new screenplay") || objective.contains("create screenplay") {
            call("createScreenplaySession", [:])
        }
        if objective.contains("new notation") || objective.contains("create notation") {
            call("createNotationSession", [:])
        }
        if objective.contains("parse screenplay"), let sid = screenplayId {
            call("parseScreenplay", ["id": sid])
        }
        if objective.contains("map cues"), let sid = screenplayId {
            call("mapScreenplayCues", ["id": sid])
        }
        if objective.contains("cue sheet"), let sid = screenplayId {
            call("getCueSheet", ["id": sid])
        }
        if (objective.contains("apply cues") || objective.contains("apply to notation")), let sid = screenplayId, let nid = notationId {
            call("applyScreenplayCuesToNotation", ["id": sid, "notation_session_id": nid])
        }
        if objective.contains("journal") {
            call("listJournal", [:])
        }
        if objective.contains("ump events"), let sess = kv["ump"] ?? kv["session"] {
            call("listUMPEvents", ["session": sess])
        }

        let body = Components.Schemas.PlanResponse(objective: req.objective, steps: steps)
        return .ok(.init(body: .json(body)))
    }

    public func planner_execute(_ input: Operations.planner_execute.Input) async throws -> Operations.planner_execute.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        // Echo execution for now; orchestration is handled by clients or gateway using FunctionCaller.
        let emptyArgsData = Data("{}".utf8)
        let results: [Components.Schemas.FunctionCallResult] = req.steps.compactMap { call in
            let encoded = (try? JSONEncoder().encode(call.arguments)) ?? emptyArgsData
            guard let args = try? JSONDecoder().decode(Components.Schemas.FunctionCallResult.argumentsPayload.self, from: encoded) else { return nil }
            return Components.Schemas.FunctionCallResult(step: call.name, arguments: args, output: "planned")
        }
        let body = Components.Schemas.ExecutionResult(results: results)
        return .ok(.init(body: .json(body)))
    }

    public func planner_list_corpora(_ input: Operations.planner_list_corpora.Input) async throws -> Operations.planner_list_corpora.Output {
        let (_, corpora) = try await persistence.listCorpora()
        return .ok(.init(body: .json(.init(corpora))))
    }

    public func get_reflection_history(_ input: Operations.get_reflection_history.Input) async throws -> Operations.get_reflection_history.Output {
        let corpusId = input.path.corpus_id
        let (_, list) = try await persistence.listReflections(corpusId: corpusId)
        let items = list.map { Components.Schemas.ReflectionItem(timestamp: String($0.ts), content: $0.content) }
        let body = Components.Schemas.HistoryListResponse(reflections: items)
        return .ok(.init(body: .json(body)))
    }

    public func get_semantic_arc(_ input: Operations.get_semantic_arc.Input) async throws -> Operations.get_semantic_arc.Output {
        let corpusId = input.path.corpus_id
        let (_, list) = try await persistence.listReflections(corpusId: corpusId)
        let obj: [String: Any] = ["corpus_id": corpusId, "total": list.count]
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let payload = try? JSONDecoder().decode(Operations.get_semantic_arc.Output.Ok.Body.jsonPayload.self, from: data) {
            return .ok(.init(body: .json(payload)))
        }
        return .undocumented(statusCode: 500, OpenAPIRuntime.UndocumentedPayload())
    }

    public func post_reflection(_ input: Operations.post_reflection.Input) async throws -> Operations.post_reflection.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let reflection = Reflection(corpusId: req.corpus_id, reflectionId: UUID().uuidString, question: req.message, content: req.message)
        _ = try await persistence.addReflection(reflection)
        let item = Components.Schemas.ReflectionItem(timestamp: String(reflection.ts), content: reflection.content)
        return .ok(.init(body: .json(item)))
    }

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        return .ok(.init(body: .plainText(HTTPBody("planner_requests_total 0\n"))))
    }
}
