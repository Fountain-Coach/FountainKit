import Foundation
import OpenAPIRuntime
import FountainStoreClient

public struct BootstrapOpenAPI: APIProtocol, @unchecked Sendable {
    let persistence: FountainStoreClient

    public init(persistence: FountainStoreClient) {
        self.persistence = persistence
    }

    // MARK: - Helpers

    private func defaultRoles() -> Components.Schemas.RoleDefaults {
        let drift = Components.Schemas.RoleDefaults.driftPayload(
            rawValue: "You are Drift, FountainAI’s baseline-drift detective. Compare a new baseline snapshot against prior versions to detect narrative or thematic drift and report the most significant changes."
        )!
        let semanticArc = Components.Schemas.RoleDefaults.semantic_arcPayload(
            rawValue: "You are Semantic Arc, tasked with tracing the corpus’s overarching narrative arc. Review the corpus history and synthesize a high-level storyline that highlights major turning points and transitions."
        )!
        let patterns = Components.Schemas.RoleDefaults.patternsPayload(
            rawValue: "You are Patterns, a spotter of recurring motifs, themes, or rhetorical structures. Inspect the corpus and list the strongest patterns you find."
        )!
        let history = Components.Schemas.RoleDefaults.historyPayload(
            rawValue: "You are History, the curator of past reflections and events. Maintain a chronological log showing how the corpus has grown and changed, focusing on context useful for future analysis."
        )!
        let viewCreator = Components.Schemas.RoleDefaults.view_creatorPayload(
            rawValue: "You are View Creator, responsible for assembling human-friendly views of the corpus and analyses. Produce a simple markdown or tabular view to help a human browse the information."
        )!
        return Components.Schemas.RoleDefaults(
            drift: drift,
            semantic_arc: semanticArc,
            patterns: patterns,
            history: history,
            view_creator: viewCreator
        )
    }

    // MARK: - Operations

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = "bootstrap_uptime_seconds \(uptime)\n"
        return .ok(.init(body: .plainText(HTTPBody(body))))
    }

    public func bootstrapInitializeCorpus(_ input: Operations.bootstrapInitializeCorpus.Input) async throws -> Operations.bootstrapInitializeCorpus.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload())
        }
        // 1) Create corpus
        let created = try await persistence.createCorpus(.init(corpusId: req.corpusId))
        // 2) Seed default roles
        let roles = defaultRoles()
        let roleDocs: [Role] = [
            .init(corpusId: req.corpusId, name: "drift", prompt: roles.drift.rawValue),
            .init(corpusId: req.corpusId, name: "semantic_arc", prompt: roles.semantic_arc.rawValue),
            .init(corpusId: req.corpusId, name: "patterns", prompt: roles.patterns.rawValue),
            .init(corpusId: req.corpusId, name: "history", prompt: roles.history.rawValue),
            .init(corpusId: req.corpusId, name: "view_creator", prompt: roles.view_creator.rawValue)
        ]
        _ = try await persistence.seedDefaultRoles(corpusId: req.corpusId, defaults: roleDocs)
        let out = Components.Schemas.InitOut(message: "corpus \(created.corpusId) initialized and roles seeded")
        return .ok(.init(body: .json(out)))
    }

    public func bootstrapSeedRoles(_ input: Operations.bootstrapSeedRoles.Input) async throws -> Operations.bootstrapSeedRoles.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload())
        }
        let roles = defaultRoles()
        let roleDocs: [Role] = [
            .init(corpusId: req.corpusId, name: "drift", prompt: roles.drift.rawValue),
            .init(corpusId: req.corpusId, name: "semantic_arc", prompt: roles.semantic_arc.rawValue),
            .init(corpusId: req.corpusId, name: "patterns", prompt: roles.patterns.rawValue),
            .init(corpusId: req.corpusId, name: "history", prompt: roles.history.rawValue),
            .init(corpusId: req.corpusId, name: "view_creator", prompt: roles.view_creator.rawValue)
        ]
        _ = try await persistence.seedDefaultRoles(corpusId: req.corpusId, defaults: roleDocs)
        return .ok(.init(body: .json(roles)))
    }

    public func seedRoles(_ input: Operations.seedRoles.Input) async throws -> Operations.seedRoles.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload())
        }
        let roles = defaultRoles()
        let roleDocs: [Role] = [
            .init(corpusId: req.corpusId, name: "drift", prompt: roles.drift.rawValue),
            .init(corpusId: req.corpusId, name: "semantic_arc", prompt: roles.semantic_arc.rawValue),
            .init(corpusId: req.corpusId, name: "patterns", prompt: roles.patterns.rawValue),
            .init(corpusId: req.corpusId, name: "history", prompt: roles.history.rawValue),
            .init(corpusId: req.corpusId, name: "view_creator", prompt: roles.view_creator.rawValue)
        ]
        _ = try await persistence.seedDefaultRoles(corpusId: req.corpusId, defaults: roleDocs)
        return .ok(.init(body: .json(roles)))
    }

    public func bootstrapAddBaseline(_ input: Operations.bootstrapAddBaseline.Input) async throws -> Operations.bootstrapAddBaseline.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload())
        }
        // Store baseline
        _ = try await persistence.addBaseline(.init(corpusId: req.corpusId, baselineId: req.baselineId, content: req.content))
        // Fire-and-forget drift/patterns persistence jobs
        let cid = req.corpusId
        let bid = req.baselineId
        Task.detached { [p = persistence] in
            _ = try? await p.addDrift(.init(corpusId: cid, driftId: "\(bid)-drift", content: "auto-generated drift"))
            _ = try? await p.addPatterns(.init(corpusId: cid, patternsId: "\(bid)-patterns", content: "auto-generated patterns"))
        }
        // Minimal JSON acknowledgement
        if let container = try? OpenAPIRuntime.OpenAPIValueContainer(unvalidatedValue: ["status": "queued"]) {
            return .ok(.init(body: .json(container)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }
}
