import Foundation
import FountainStoreClient
import FountainRuntime

public struct InitIn: Codable { public let corpusId: String }
public struct InitOut: Codable { public let message: String }
public struct BaselineRequest: Codable { public let corpusId: String; public let baselineId: String; public let content: String }
public struct DriftRequest: Codable { public let corpusId: String; public let driftId: String; public let content: String }
public struct PatternsRequest: Codable { public let corpusId: String; public let patternsId: String; public let content: String }
public struct ReflectionRequest: Codable { public let corpusId: String; public let reflectionId: String; public let question: String; public let content: String }
public struct ReflectionSummaryResponse: Codable { public let message: String }
public struct HistorySummaryResponse: Codable { public let summary: String }

public struct HTTPRequest: Sendable { public let method: String; public let path: String; public let body: Data; public init(method: String, path: String, body: Data = Data()) { self.method = method; self.path = path; self.body = body } }
public struct HTTPResponse: Sendable { public let status: Int; public let headers: [String:String]; public let body: Data; public init(status: Int, headers: [String:String] = [:], body: Data = Data()) { self.status = status; self.headers = headers; self.body = body } }

public final class AwarenessRouter: @unchecked Sendable {
    let persistence: FountainStoreClient
    public init(persistence: FountainStoreClient) { self.persistence = persistence }

    // MARK: - Operation Handlers

    public func health_health_get() async throws -> HTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: ["status": "ok"])
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func initializeCorpus(_ input: InitIn) async throws -> HTTPResponse {
        let req = CorpusCreateRequest(corpusId: input.corpusId)
        let resp = try await persistence.createCorpus(req)
        let out = InitOut(message: "corpus \(resp.corpusId) created")
        let data = try JSONEncoder().encode(out)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func listHistory(corpusId: String) async throws -> HTTPResponse {
        let (bCount, _) = try await persistence.listBaselines(corpusId: corpusId)
        let (rCount, _) = try await persistence.listReflections(corpusId: corpusId)
        let summary = "baselines=\(bCount), reflections=\(rCount)"
        let data = try JSONEncoder().encode(HistorySummaryResponse(summary: summary))
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func summarizeHistory(corpusId: String) async throws -> HTTPResponse {
        let (bCount, _) = try await persistence.listBaselines(corpusId: corpusId)
        let (rCount, _) = try await persistence.listReflections(corpusId: corpusId)
        let summary = "summary for \(corpusId): baselines=\(bCount), reflections=\(rCount)"
        let data = try JSONEncoder().encode(HistorySummaryResponse(summary: summary))
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func listHistoryAnalytics(corpusId: String) async throws -> HTTPResponse {
        let (bt, baselines) = try await persistence.listBaselines(corpusId: corpusId, limit: 1000, offset: 0)
        let (rt, reflections) = try await persistence.listReflections(corpusId: corpusId, limit: 1000, offset: 0)
        let (dt, drifts) = try await persistence.listDrifts(corpusId: corpusId, limit: 1000, offset: 0)
        let (pt, patterns) = try await persistence.listPatterns(corpusId: corpusId, limit: 1000, offset: 0)
        var events: [[String: Any]] = []
        for b in baselines { events.append(["type": "baseline", "id": b.baselineId, "content_len": b.content.count, "ts": b.ts]) }
        for r in reflections { events.append(["type": "reflection", "id": r.reflectionId, "question": r.question, "ts": r.ts]) }
        for d in drifts { events.append(["type": "drift", "id": d.driftId, "content_len": d.content.count, "ts": d.ts]) }
        for p in patterns { events.append(["type": "patterns", "id": p.patternsId, "content_len": p.content.count, "ts": p.ts]) }
        events.sort { ((($0["ts"] as? Double) ?? 0) < (($1["ts"] as? Double) ?? 0)) }
        let obj: [String: Any] = ["total": bt + rt + dt + pt, "events": events]
        let data = try JSONSerialization.data(withJSONObject: obj)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func readSemanticArc(corpusId: String) async throws -> HTTPResponse {
        // Core store-derived counts
        let (pagesCount, _) = try await persistence.listPages(corpusId: corpusId, limit: 1, offset: 0)
        let (segmentsCount, _) = try await persistence.listSegments(corpusId: corpusId, limit: 1, offset: 0)
        let (entitiesCount, _) = try await persistence.listEntities(corpusId: corpusId, limit: 1, offset: 0)
        let (analysesCount, _) = try await persistence.listAnalyses(corpusId: corpusId, limit: 1, offset: 0)

        // History/curation signal counts
        let (baselinesCount, _) = try await persistence.listBaselines(corpusId: corpusId, limit: 1000, offset: 0)
        let (reflectionsCount, _) = try await persistence.listReflections(corpusId: corpusId, limit: 1000, offset: 0)
        let (driftsCount, _) = try await persistence.listDrifts(corpusId: corpusId, limit: 1000, offset: 0)
        let (patternsCount, _) = try await persistence.listPatterns(corpusId: corpusId, limit: 1000, offset: 0)

        // Build a richer semantic arc across ingestion→structure→index→curation phases
        let phases: [(String, Int)] = [
            ("ingestion/pages", pagesCount),
            ("structure/segments", segmentsCount),
            ("index/entities", entitiesCount),
            ("analysis/summaries", analysesCount),
            ("curation/baselines", baselinesCount),
            ("evolution/drift", driftsCount),
            ("reasoning/reflections", reflectionsCount),
            ("patterns", patternsCount)
        ]
        let total = max(phases.reduce(0) { $0 + $1.1 }, 1)
        let arc: [[String: Any]] = phases.map { (name, weight) in
            ["phase": name, "weight": weight, "pct": Double(weight) / Double(total)]
        }
        let obj: [String: Any] = [
            "arc": arc,
            "total": total,
            "counts": [
                "pages": pagesCount,
                "segments": segmentsCount,
                "entities": entitiesCount,
                "analyses": analysesCount,
                "baselines": baselinesCount,
                "reflections": reflectionsCount,
                "drifts": driftsCount,
                "patterns": patternsCount
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func streamHistoryAnalytics(isSSE: Bool) async throws -> HTTPResponse {
        if isSSE {
            let sse = """
            event: tick
            data: {"status":"started","kind":"tick"}

            : heartbeat

            event: complete
            data: {}

            """
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"], body: Data(sse.utf8))
        } else {
            let data = try JSONSerialization.data(withJSONObject: [:])
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        }
    }

    public func metrics_metrics_get() async throws -> HTTPResponse {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = Data("awareness_uptime_seconds \(uptime)\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let pathOnly = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? request.path
        switch (request.method, pathOnly) {
        case ("GET", "/health"):
            return try await health_health_get()
        case ("GET", "/live"):
            let data = try JSONSerialization.data(withJSONObject: ["status": "live"])
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        case ("GET", "/ready"):
            let data = try JSONSerialization.data(withJSONObject: ["status": "ready"])
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        case ("GET", "/metrics"):
            return try await metrics_metrics_get()
        case ("POST", "/corpus/init"):
            if let input = try? JSONDecoder().decode(InitIn.self, from: request.body) {
                return try await initializeCorpus(input)
            }
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
        case ("POST", "/corpus/baseline"):
            if let input = try? JSONDecoder().decode(BaselineRequest.self, from: request.body) {
                _ = try await persistence.addBaseline(.init(corpusId: input.corpusId, baselineId: input.baselineId, content: input.content))
                let data = try JSONSerialization.data(withJSONObject: ["message": "ok"]) 
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
        case ("POST", "/corpus/drift"):
            if let input = try? JSONDecoder().decode(DriftRequest.self, from: request.body) {
                _ = try await persistence.addDrift(.init(corpusId: input.corpusId, driftId: input.driftId, content: input.content))
                let data = try JSONSerialization.data(withJSONObject: ["message": "ok"]) 
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
        case ("POST", "/corpus/patterns"):
            if let input = try? JSONDecoder().decode(PatternsRequest.self, from: request.body) {
                _ = try await persistence.addPatterns(.init(corpusId: input.corpusId, patternsId: input.patternsId, content: input.content))
                let data = try JSONSerialization.data(withJSONObject: ["message": "ok"]) 
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
        case ("POST", "/corpus/reflections"):
            if let input = try? JSONDecoder().decode(ReflectionRequest.self, from: request.body) {
                _ = try await persistence.addReflection(.init(corpusId: input.corpusId, reflectionId: input.reflectionId, question: input.question, content: input.content))
                let data = try JSONSerialization.data(withJSONObject: ["message": "ok"]) 
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
            return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
        default:
            break
        }
        // Parameterized routes
        let segments = pathOnly.split(separator: "/").map(String.init)
        if request.method == "GET" && segments.count == 3 && segments[0] == "corpus" && segments[1] == "reflections" {
            let corpusId = segments[2]
            let (total, _) = try await persistence.listReflections(corpusId: corpusId)
            let data = try JSONEncoder().encode(ReflectionSummaryResponse(message: "\(total) reflections"))
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        }
        if request.method == "DELETE" && segments.count == 2 && segments[0] == "corpus" {
            let corpusId = segments[1]
            try await persistence.deleteCorpus(corpusId)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }
        if request.method == "GET" && segments.count == 3 && segments[0] == "corpus" && segments[1] == "history" {
            return try await listHistory(corpusId: segments[2])
        }
        if request.method == "GET" && segments.count == 3 && segments[0] == "corpus" && segments[1] == "summary" {
            return try await summarizeHistory(corpusId: segments[2])
        }
        if request.method == "GET" && pathOnly == "/corpus/history" {
            let qp = Self.queryParams(from: request.path)
            guard let corpusId = qp["corpus_id"], !corpusId.isEmpty else {
                return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
            }
            return try await listHistoryAnalytics(corpusId: corpusId)
        }
        if request.method == "GET" && pathOnly == "/corpus/semantic-arc" {
            let qp = Self.queryParams(from: request.path)
            guard let corpusId = qp["corpus_id"], !corpusId.isEmpty else {
                return HTTPResponse(status: 422, headers: ["Content-Type": "application/json"], body: Data())
            }
            return try await readSemanticArc(corpusId: corpusId)
        }
        if request.method == "GET" && pathOnly == "/corpus/history/stream" {
            let sse = request.path.contains("sse=1")
            return try await streamHistoryAnalytics(isSSE: sse)
        }
        return HTTPResponse(status: 404)
    }
}

extension AwarenessRouter {
    static func queryParams(from path: String) -> [String: String] {
        guard let qIndex = path.firstIndex(of: "?") else { return [:] }
        let query = path[path.index(after: qIndex)...]
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[1].isEmpty { out[parts[0]] = parts[1] }
        }
        return out
    }
}

public func makeAwarenessKernel(service svc: FountainStoreClient) -> HTTPKernel {
    let router = AwarenessRouter(persistence: svc)
    return HTTPKernel { req in
        let ar = HTTPRequest(method: req.method, path: req.path, body: req.body)
        let resp = try await router.route(ar)
        return FountainRuntime.HTTPResponse(status: resp.status, headers: resp.headers, body: resp.body)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
