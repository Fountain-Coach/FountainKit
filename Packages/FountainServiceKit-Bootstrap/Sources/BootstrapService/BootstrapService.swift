import Foundation
import FountainStoreClient
import FountainRuntime

public struct InitIn: Codable { public let corpusId: String }
public struct InitOut: Codable { public let message: String }
public struct BaselineIn: Codable { public let corpusId: String; public let baselineId: String; public let content: String }
public struct RoleInitRequest: Codable { public let corpusId: String }
public struct RoleDefaults: Codable { public let drift: String; public let semantic_arc: String; public let patterns: String; public let history: String; public let view_creator: String }

public struct HTTPRequest: Sendable { public let method: String; public let path: String; public let body: Data; public init(method: String, path: String, body: Data = Data()) { self.method = method; self.path = path; self.body = body } }
public struct HTTPResponse: Sendable { public let status: Int; public let headers: [String:String]; public let body: Data; public init(status: Int, headers: [String:String] = [:], body: Data = Data()) { self.status = status; self.headers = headers; self.body = body } }

public final class BootstrapRouter: @unchecked Sendable {
    let persistence: FountainStoreClient
    public init(persistence: FountainStoreClient) { self.persistence = persistence }

    private func defaultRoles() -> RoleDefaults {
        RoleDefaults(
            drift: "You are Drift, FountainAI’s baseline-drift detective. Compare a new baseline snapshot against prior versions to detect narrative or thematic drift and report the most significant changes.",
            semantic_arc: "You are Semantic Arc, tasked with tracing the corpus’s overarching narrative arc. Review the corpus history and synthesize a high-level storyline that highlights major turning points and transitions.",
            patterns: "You are Patterns, a spotter of recurring motifs, themes, or rhetorical structures. Inspect the corpus and list the strongest patterns you find.",
            history: "You are History, the curator of past reflections and events. Maintain a chronological log showing how the corpus has grown and changed, focusing on context useful for future analysis.",
            view_creator: "You are View Creator, responsible for assembling human-friendly views of the corpus and analyses. Produce a simple markdown or tabular view to help a human browse the information."
        )
    }

    // MARK: - Operation Handlers

    /// `GET /metrics`
    ///
    /// Serves a minimal Prometheus text exposition payload. The
    /// implementation mirrors the other services in this repository and
    /// simply exposes the current process uptime.
    public func metrics_metrics_get() async throws -> HTTPResponse {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = Data("bootstrap_uptime_seconds \(uptime)\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }

    /// `POST /bootstrap/corpus/init`
    ///
    /// Creates a new empty corpus and seeds the default GPT role prompts.
    public func bootstrapInitializeCorpus(_ input: InitIn) async throws -> HTTPResponse {
        let req = CorpusCreateRequest(corpusId: input.corpusId)
        let resp = try await persistence.createCorpus(req)
        let roles = defaultRoles()
        let roleDocs: [Role] = [
            .init(corpusId: input.corpusId, name: "drift", prompt: roles.drift),
            .init(corpusId: input.corpusId, name: "semantic_arc", prompt: roles.semantic_arc),
            .init(corpusId: input.corpusId, name: "patterns", prompt: roles.patterns),
            .init(corpusId: input.corpusId, name: "history", prompt: roles.history),
            .init(corpusId: input.corpusId, name: "view_creator", prompt: roles.view_creator)
        ]
        _ = try await persistence.seedDefaultRoles(corpusId: input.corpusId, defaults: roleDocs)
        let out = InitOut(message: "corpus \(resp.corpusId) initialized and roles seeded")
        let data = try JSONEncoder().encode(out)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// Shared helper used by both role seeding endpoints.
    private func seed(_ input: RoleInitRequest) async throws -> HTTPResponse {
        let roles = defaultRoles()
        let roleDocs: [Role] = [
            .init(corpusId: input.corpusId, name: "drift", prompt: roles.drift),
            .init(corpusId: input.corpusId, name: "semantic_arc", prompt: roles.semantic_arc),
            .init(corpusId: input.corpusId, name: "patterns", prompt: roles.patterns),
            .init(corpusId: input.corpusId, name: "history", prompt: roles.history),
            .init(corpusId: input.corpusId, name: "view_creator", prompt: roles.view_creator)
        ]
        _ = try await persistence.seedDefaultRoles(corpusId: input.corpusId, defaults: roleDocs)
        let data = try JSONEncoder().encode(roles)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// `POST /bootstrap/roles/seed`
    public func bootstrapSeedRoles(_ input: RoleInitRequest) async throws -> HTTPResponse {
        try await seed(input)
    }

    /// `POST /bootstrap/roles`
    public func seedRoles(_ input: RoleInitRequest) async throws -> HTTPResponse {
        try await seed(input)
    }

    /// `POST /bootstrap/baseline`
    ///
    /// Adds a new baseline and optionally streams back synthetic drift and
    /// pattern events when `sse=1` is present in the query string.
    public func bootstrapAddBaseline(_ input: BaselineIn, isSSE: Bool) async throws -> HTTPResponse {
        _ = try await persistence.addBaseline(.init(corpusId: input.corpusId, baselineId: input.baselineId, content: input.content))
        let cid = input.corpusId
        let bid = input.baselineId
        Task {
            _ = try? await persistence.addDrift(.init(corpusId: cid, driftId: "\(bid)-drift", content: "auto-generated drift"))
            _ = try? await persistence.addPatterns(.init(corpusId: cid, patternsId: "\(bid)-patterns", content: "auto-generated patterns"))
        }
        if isSSE {
            let sse = """
            event: drift
            data: {"status":"started","kind":"drift"}

            event: patterns
            data: {"status":"started","kind":"patterns"}

            event: complete
            data: {}

            : heartbeat

            """
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache", "X-Chunked-SSE": "1"], body: Data(sse.utf8))
        } else {
            let data = try JSONSerialization.data(withJSONObject: [:])
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        }
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let pathOnly = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? request.path
        switch (request.method, pathOnly) {
        case ("GET", "/health"):
            let data = try JSONSerialization.data(withJSONObject: ["status": "ok"]) 
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        case ("GET", "/live"):
            let data = try JSONSerialization.data(withJSONObject: ["status": "live"]) 
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        case ("GET", "/ready"):
            let data = try JSONSerialization.data(withJSONObject: ["status": "ready"]) 
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        case ("GET", "/metrics"):
            return try await metrics_metrics_get()
        case ("POST", "/bootstrap/corpus/init"):
            guard let input = try? JSONDecoder().decode(InitIn.self, from: request.body) else {
                return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
            }
            return try await bootstrapInitializeCorpus(input)
        case ("POST", "/bootstrap/roles/seed"):
            guard let input = try? JSONDecoder().decode(RoleInitRequest.self, from: request.body) else {
                return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
            }
            return try await bootstrapSeedRoles(input)
        case ("POST", "/bootstrap/roles"):
            guard let input = try? JSONDecoder().decode(RoleInitRequest.self, from: request.body) else {
                return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
            }
            return try await seedRoles(input)
        case ("POST", "/bootstrap/baseline"):
            guard let input = try? JSONDecoder().decode(BaselineIn.self, from: request.body) else {
                return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
            }
            let isSSE = request.path.contains("sse=1")
            return try await bootstrapAddBaseline(input, isSSE: isSSE)
        default:
            return HTTPResponse(status: 404)
        }
    }
}

public func makeBootstrapKernel(service svc: FountainStoreClient) -> HTTPKernel {
    let router = BootstrapRouter(persistence: svc)
    return HTTPKernel { req in
        let br = HTTPRequest(method: req.method, path: req.path, body: req.body)
        let resp = try await router.route(br)
        return FountainRuntime.HTTPResponse(status: resp.status, headers: resp.headers, body: resp.body)
    }
}

public extension BootstrapRouter {
    func prepareBaselineEvents(input: BaselineIn) async throws -> [String] {
        _ = try await self.persistence.addBaseline(.init(corpusId: input.corpusId, baselineId: input.baselineId, content: input.content))
        let cid = input.corpusId
        let bid = input.baselineId
        Task {
            _ = try? await persistence.addDrift(.init(corpusId: cid, driftId: "\(bid)-drift", content: "auto-generated drift"))
            _ = try? await persistence.addPatterns(.init(corpusId: cid, patternsId: "\(bid)-patterns", content: "auto-generated patterns"))
        }
        return [
            "event: drift\ndata: {\"status\":\"started\",\"kind\":\"drift\"}\n\n",
            "event: patterns\ndata: {\"status\":\"started\",\"kind\":\"patterns\"}\n\n",
            "event: complete\ndata: {}\n\n"
        ]
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
