import Foundation
import OpenAPIRuntime
import FountainStoreClient

public struct AwarenessOpenAPI: APIProtocol, @unchecked Sendable {
    let persistence: FountainStoreClient

    public init(persistence: FountainStoreClient) {
        self.persistence = persistence
    }

    // MARK: - Simple helpers

    private func okObject(_ dict: [String: (any Sendable)?]) -> OpenAPIRuntime.OpenAPIObjectContainer? {
        try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: dict)
    }

    // MARK: - Operations

    public func health_health_get(_ input: Operations.health_health_get.Input) async throws -> Operations.health_health_get.Output {
        if let body = okObject(["status": "ok"]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func initializeCorpus(_ input: Operations.initializeCorpus.Input) async throws -> Operations.initializeCorpus.Output {
        guard case let .json(req) = input.body else { return .unprocessableContent }
        let created = try await persistence.createCorpus(.init(corpusId: req.corpusId))
        let out = Components.Schemas.InitOut(message: "corpus \(created.corpusId) created")
        return .ok(.init(body: .json(out)))
    }

    public func addBaseline(_ input: Operations.addBaseline.Input) async throws -> Operations.addBaseline.Output {
        guard case let .json(req) = input.body else { return .unprocessableContent }
        _ = try await persistence.addBaseline(.init(corpusId: req.corpusId, baselineId: req.baselineId, content: req.content))
        if let body = okObject(["message": "ok"]) { return .ok(.init(body: .json(body))) }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func addDrift(_ input: Operations.addDrift.Input) async throws -> Operations.addDrift.Output {
        guard case let .json(req) = input.body else { return .unprocessableContent }
        _ = try await persistence.addDrift(.init(corpusId: req.corpusId, driftId: req.driftId, content: req.content))
        if let body = okObject(["message": "ok"]) { return .ok(.init(body: .json(body))) }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func addPatterns(_ input: Operations.addPatterns.Input) async throws -> Operations.addPatterns.Output {
        guard case let .json(req) = input.body else { return .unprocessableContent }
        _ = try await persistence.addPatterns(.init(corpusId: req.corpusId, patternsId: req.patternsId, content: req.content))
        if let body = okObject(["message": "ok"]) { return .ok(.init(body: .json(body))) }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func addReflection(_ input: Operations.addReflection.Input) async throws -> Operations.addReflection.Output {
        guard case let .json(req) = input.body else { return .unprocessableContent }
        _ = try await persistence.addReflection(.init(corpusId: req.corpusId, reflectionId: req.reflectionId, question: req.question, content: req.content))
        if let body = okObject(["message": "ok"]) { return .ok(.init(body: .json(body))) }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func listReflections(_ input: Operations.listReflections.Input) async throws -> Operations.listReflections.Output {
        let cid = input.path.corpus_id
        let (total, _) = try await persistence.listReflections(corpusId: cid)
        let out = Components.Schemas.ReflectionSummaryResponse(message: "\(total) reflections")
        return .ok(.init(body: .json(out)))
    }

    public func listHistory(_ input: Operations.listHistory.Input) async throws -> Operations.listHistory.Output {
        let cid = input.path.corpus_id
        let (bCount, _) = try await persistence.listBaselines(corpusId: cid)
        let (rCount, _) = try await persistence.listReflections(corpusId: cid)
        let summary = "baselines=\(bCount), reflections=\(rCount)"
        let out = Components.Schemas.HistorySummaryResponse(summary: summary)
        return .ok(.init(body: .json(out)))
    }

    public func summarizeHistory(_ input: Operations.summarizeHistory.Input) async throws -> Operations.summarizeHistory.Output {
        let cid = input.path.corpus_id
        let (bCount, _) = try await persistence.listBaselines(corpusId: cid)
        let (rCount, _) = try await persistence.listReflections(corpusId: cid)
        let out = Components.Schemas.HistorySummaryResponse(summary: "summary for \(cid): baselines=\(bCount), reflections=\(rCount)")
        return .ok(.init(body: .json(out)))
    }

    public func listHistoryAnalytics(_ input: Operations.listHistoryAnalytics.Input) async throws -> Operations.listHistoryAnalytics.Output {
        let cid = input.query.corpus_id
        let (bt, baselines) = try await persistence.listBaselines(corpusId: cid, limit: 1000, offset: 0)
        let (rt, reflections) = try await persistence.listReflections(corpusId: cid, limit: 1000, offset: 0)
        let (dt, drifts) = try await persistence.listDrifts(corpusId: cid, limit: 1000, offset: 0)
        let (pt, patterns) = try await persistence.listPatterns(corpusId: cid, limit: 1000, offset: 0)
        var events: [[String: (any Sendable)?]] = []
        for b in baselines { events.append(["type": "baseline", "id": b.baselineId, "content_len": b.content.count, "ts": b.ts]) }
        for r in reflections { events.append(["type": "reflection", "id": r.reflectionId, "question": r.question, "ts": r.ts]) }
        for d in drifts { events.append(["type": "drift", "id": d.driftId, "content_len": d.content.count, "ts": d.ts]) }
        for p in patterns { events.append(["type": "patterns", "id": p.patternsId, "content_len": p.content.count, "ts": p.ts]) }
        events.sort { (a, b) in
            let at = (a["ts"] as? Double) ?? 0
            let bt = (b["ts"] as? Double) ?? 0
            return at < bt
        }
        if let body = okObject(["total": bt + rt + dt + pt, "events": events]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func readSemanticArc(_ input: Operations.readSemanticArc.Input) async throws -> Operations.readSemanticArc.Output {
        let cid = input.query.corpus_id
        let (bt, _) = try await persistence.listBaselines(corpusId: cid, limit: 1000, offset: 0)
        let (rt, _) = try await persistence.listReflections(corpusId: cid, limit: 1000, offset: 0)
        let (dt, _) = try await persistence.listDrifts(corpusId: cid, limit: 1000, offset: 0)
        let (pt, _) = try await persistence.listPatterns(corpusId: cid, limit: 1000, offset: 0)
        if let body = okObject(["baselines": bt, "reflections": rt, "drifts": dt, "patterns": pt]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func streamHistoryAnalytics(_ input: Operations.streamHistoryAnalytics.Input) async throws -> Operations.streamHistoryAnalytics.Output {
        if let body = okObject(["status": "started"]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func metrics_metrics_get(_ input: Operations.metrics_metrics_get.Input) async throws -> Operations.metrics_metrics_get.Output {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = "awareness_uptime_seconds \(uptime)\n"
        return .ok(.init(body: .plainText(HTTPBody(body))))
    }
}

