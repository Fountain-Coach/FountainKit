import Foundation
import FountainRuntime
import FountainStoreClient

public func metrics_metrics_get() async -> HTTPResponse {
    let uptime = Int(ProcessInfo.processInfo.systemUptime)
    let body = Data("persist_uptime_seconds \(uptime)\n".utf8)
    return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
}

public func listFunctionsInCorpus(service svc: FountainStoreClient, corpusId: String, limit: Int, offset: Int, q: String?) async throws -> HTTPResponse {
    let (total, functions) = try await svc.listFunctions(corpusId: corpusId, limit: limit, offset: offset, q: q)
    let obj: [String: Any] = [
        "total": total,
        "functions": try functions.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
    ]
    let json = try JSONSerialization.data(withJSONObject: obj)
    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
}

public func makePersistKernel(service svc: FountainStoreClient) -> HTTPKernel {
    HTTPKernel { req in
        let pathOnly = req.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? req.path
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: true)
        do {
            switch (req.method, segments) {
            case ("GET", ["metrics"]):
                return await metrics_metrics_get()

            case ("GET", ["capabilities"]):
                let caps = try await svc.capabilities()
                let json = try JSONEncoder().encode(caps)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", ["corpora"]):
                let qp = queryParams(from: req.path)
                let limit = min(max(Int(qp["limit"] ?? "50") ?? 50, 1), 200)
                let offset = max(Int(qp["offset"] ?? "0") ?? 0, 0)
                let (total, corpora) = try await svc.listCorpora(limit: limit, offset: offset)
                let json = try JSONSerialization.data(withJSONObject: ["total": total, "corpora": corpora])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("POST", ["corpora"]):
                let reqObj = try JSONDecoder().decode(CorpusCreateRequest.self, from: req.body)
                let resp = try await svc.createCorpus(reqObj)
                let json = try JSONEncoder().encode(resp)
                return HTTPResponse(status: 201, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", let seg) where seg.count == 3 && seg[0] == "corpora" && seg[2] == "baselines":
                let corpusId = String(seg[1])
                let qp = queryParams(from: req.path)
                let limit = min(max(Int(qp["limit"] ?? "50") ?? 50, 1), 200)
                let offset = max(Int(qp["offset"] ?? "0") ?? 0, 0)
                let (total, baselines) = try await svc.listBaselines(corpusId: corpusId, limit: limit, offset: offset)
                let obj: [String: Any] = [
                    "total": total,
                    "baselines": try baselines.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
                ]
                let json = try JSONSerialization.data(withJSONObject: obj)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("POST", let seg) where seg.count == 3 && seg[0] == "corpora" && seg[2] == "baselines":
                let corpusId = String(seg[1])
                var baseline = try JSONDecoder().decode(Baseline.self, from: req.body)
                if baseline.corpusId != corpusId {
                    baseline = Baseline(corpusId: corpusId, baselineId: baseline.baselineId, content: baseline.content)
                }
                let resp = try await svc.addBaseline(baseline)
                let json = try JSONEncoder().encode(resp)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", let seg) where seg.count == 3 && seg[0] == "corpora" && seg[2] == "reflections":
                let corpusId = String(seg[1])
                let qp = queryParams(from: req.path)
                let limit = min(max(Int(qp["limit"] ?? "50") ?? 50, 1), 200)
                let offset = max(Int(qp["offset"] ?? "0") ?? 0, 0)
                let (total, reflections) = try await svc.listReflections(corpusId: corpusId, limit: limit, offset: offset)
                let obj: [String: Any] = [
                    "total": total,
                    "reflections": try reflections.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
                ]
                let json = try JSONSerialization.data(withJSONObject: obj)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("POST", let seg) where seg.count == 3 && seg[0] == "corpora" && seg[2] == "reflections":
                let corpusId = String(seg[1])
                var reflection = try JSONDecoder().decode(Reflection.self, from: req.body)
                if reflection.corpusId != corpusId {
                    reflection = Reflection(corpusId: corpusId, reflectionId: reflection.reflectionId, question: reflection.question, content: reflection.content)
                }
                let resp = try await svc.addReflection(reflection)
                let json = try JSONEncoder().encode(resp)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("POST", let seg) where seg.count == 3 && seg[0] == "corpora" && seg[2] == "functions":
                let corpusId = String(seg[1])
                struct FunctionIncoming: Codable {
                    let corpusId: String?
                    let functionId: String
                    let name: String
                    let description: String
                    let httpMethod: String
                    let httpPath: String
                }
                let incoming = try JSONDecoder().decode(FunctionIncoming.self, from: req.body)
                let function = FunctionModel(corpusId: incoming.corpusId ?? corpusId,
                                             functionId: incoming.functionId,
                                             name: incoming.name,
                                             description: incoming.description,
                                             httpMethod: incoming.httpMethod,
                                             httpPath: incoming.httpPath)
                let resp = try await svc.addFunction(function)
                let json = try JSONEncoder().encode(resp)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", ["functions"]):
                let qp = queryParams(from: req.path)
                let limit = min(max(Int(qp["limit"] ?? "50") ?? 50, 1), 200)
                let offset = max(Int(qp["offset"] ?? "0") ?? 0, 0)
                let q = qp["q"]
                let (total, functions) = try await svc.listFunctions(limit: limit, offset: offset, q: q)
                let obj: [String: Any] = [
                    "total": total,
                    "functions": try functions.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
                ]
                let json = try JSONSerialization.data(withJSONObject: obj)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", let seg) where seg.count == 3 && seg[0] == "corpora" && seg[2] == "functions":
                let corpusId = String(seg[1])
                let qp = queryParams(from: req.path)
                let limit = min(max(Int(qp["limit"] ?? "50") ?? 50, 1), 200)
                let offset = max(Int(qp["offset"] ?? "0") ?? 0, 0)
                let q = qp["q"]
                return try await listFunctionsInCorpus(service: svc, corpusId: corpusId, limit: limit, offset: offset, q: q)

            case ("GET", let seg) where seg.count == 2 && seg[0] == "functions":
                let functionId = String(seg[1])
                if let f = try await svc.getFunctionDetails(functionId: functionId) {
                    let json = try JSONEncoder().encode(f)
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
                }
                return HTTPResponse(status: 404)

            default:
                return HTTPResponse(status: 404)
            }
        } catch {
            return HTTPResponse(status: 400)
        }
    }
}

public func queryParams(from path: String) -> [String: String] {
    guard let qIndex = path.firstIndex(of: "?") else { return [:] }
    let query = path[path.index(after: qIndex)...]
    var out: [String: String] = [:]
    for pair in query.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { out[parts[0]] = parts[1] }
    }
    return out
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
