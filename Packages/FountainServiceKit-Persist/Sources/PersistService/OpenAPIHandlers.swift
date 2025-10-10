import Foundation
import OpenAPIRuntime
import FountainStoreClient

public struct PersistOpenAPI: APIProtocol, @unchecked Sendable {
    let persistence: FountainStoreClient
    public init(persistence: FountainStoreClient) { self.persistence = persistence }

    public func capabilities(_ input: Operations.capabilities.Input) async throws -> Operations.capabilities.Output {
        let caps = try await persistence.capabilities()
        let body = Components.Schemas.Capabilities(
            corpus: caps.corpus,
            documents: caps.documents,
            query: caps.query,
            transactions: caps.transactions,
            admin: caps.admin,
            experimental: caps.experimental
        )
        return .ok(.init(body: .json(body)))
    }

    public func listCorpora(_ input: Operations.listCorpora.Input) async throws -> Operations.listCorpora.Output {
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let (total, corpora) = try await persistence.listCorpora(limit: limit, offset: offset)
        let payload = Operations.listCorpora.Output.Ok.Body.jsonPayload(total: total, corpora: corpora)
        return .ok(.init(body: .json(payload)))
    }

    public func listAnalyses(_ input: Operations.listAnalyses.Input) async throws -> Operations.listAnalyses.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let (total, analyses) = try await persistence.listAnalyses(corpusId: corpusId, limit: limit, offset: offset)
        let items: [Components.Schemas.Analysis] = analyses.map { a in
            .init(value1: .init(corpusId: a.corpusId), value2: .init(analysisId: a.analysisId, pageId: a.pageId, summary: a.summary))
        }
        let payload = Operations.listAnalyses.Output.Ok.Body.jsonPayload(total: total, analyses: items)
        return .ok(.init(body: .json(payload)))
    }

    public func addAnalysis(_ input: Operations.addAnalysis.Input) async throws -> Operations.addAnalysis.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let record = AnalysisRecord(corpusId: corpusId, analysisId: req.value2.analysisId, pageId: req.value2.pageId, summary: req.value2.summary)
        let resp = try await persistence.addAnalysis(record)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func createCorpus(_ input: Operations.createCorpus.Input) async throws -> Operations.createCorpus.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let resp = try await persistence.createCorpus(.init(corpusId: req.corpusId))
        return .created(.init(body: .json(.init(corpusId: resp.corpusId, message: resp.message))))
    }

    public func listBaselines(_ input: Operations.listBaselines.Input) async throws -> Operations.listBaselines.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let (total, baselines) = try await persistence.listBaselines(corpusId: corpusId, limit: limit, offset: offset)
        let items: [Components.Schemas.Baseline] = baselines.map { b in
            .init(value1: .init(corpusId: b.corpusId), value2: .init(baselineId: b.baselineId, content: b.content))
        }
        let payload = Operations.listBaselines.Output.Ok.Body.jsonPayload(total: total, baselines: items)
        return .ok(.init(body: .json(payload)))
    }

    public func addBaseline(_ input: Operations.addBaseline.Input) async throws -> Operations.addBaseline.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let baseline = Baseline(corpusId: corpusId, baselineId: req.value2.baselineId, content: req.value2.content)
        let resp = try await persistence.addBaseline(baseline)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func listFunctionsInCorpus(_ input: Operations.listFunctionsInCorpus.Input) async throws -> Operations.listFunctionsInCorpus.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let q = input.query.q
        let (total, functions) = try await persistence.listFunctions(corpusId: corpusId, limit: limit, offset: offset, q: q)
        let items: [Components.Schemas.Function] = functions.map { f in
            .init(value1: .init(corpusId: f.corpusId),
                  value2: .init(functionId: f.functionId, name: f.name, description: f.description, httpMethod: .init(rawValue: f.httpMethod) ?? .GET, httpPath: f.httpPath))
        }
        let payload = Operations.listFunctionsInCorpus.Output.Ok.Body.jsonPayload(total: total, functions: items)
        return .ok(.init(body: .json(payload)))
    }

    public func addFunction(_ input: Operations.addFunction.Input) async throws -> Operations.addFunction.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let model = FunctionModel(corpusId: corpusId,
                                  functionId: req.value2.functionId,
                                  name: req.value2.name,
                                  description: req.value2.description,
                                  httpMethod: req.value2.httpMethod.rawValue,
                                  httpPath: req.value2.httpPath)
        let resp = try await persistence.addFunction(model)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func addReflection(_ input: Operations.addReflection.Input) async throws -> Operations.addReflection.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let reflection = Reflection(corpusId: corpusId, reflectionId: req.value2.reflectionId, question: req.value2.question, content: req.value2.content)
        let resp = try await persistence.addReflection(reflection)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func listReflections(_ input: Operations.listReflections.Input) async throws -> Operations.listReflections.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let (total, reflections) = try await persistence.listReflections(corpusId: corpusId, limit: limit, offset: offset)
        let items: [Components.Schemas.Reflection] = reflections.map { r in
            .init(value1: .init(corpusId: r.corpusId), value2: .init(reflectionId: r.reflectionId, question: r.question, content: r.content))
        }
        let payload = Operations.listReflections.Output.Ok.Body.jsonPayload(total: total, reflections: items)
        return .ok(.init(body: .json(payload)))
    }

    public func listFunctions(_ input: Operations.listFunctions.Input) async throws -> Operations.listFunctions.Output {
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let q = input.query.q
        let (total, functions) = try await persistence.listFunctions(limit: limit, offset: offset, q: q)
        let items: [Components.Schemas.Function] = functions.map { f in
            .init(value1: .init(corpusId: f.corpusId),
                  value2: .init(functionId: f.functionId, name: f.name, description: f.description, httpMethod: .init(rawValue: f.httpMethod) ?? .GET, httpPath: f.httpPath))
        }
        let payload = Operations.listFunctions.Output.Ok.Body.jsonPayload(total: total, functions: items)
        return .ok(.init(body: .json(payload)))
    }

    public func getFunctionDetails(_ input: Operations.getFunctionDetails.Input) async throws -> Operations.getFunctionDetails.Output {
        let id = input.path.functionId
        if let f = try await persistence.getFunctionDetails(functionId: id) {
            let body = Components.Schemas.Function(value1: .init(corpusId: f.corpusId), value2: .init(functionId: f.functionId, name: f.name, description: f.description, httpMethod: .init(rawValue: f.httpMethod) ?? .GET, httpPath: f.httpPath))
            return .ok(.init(body: .json(body)))
        }
        let err = Components.Responses.ErrorResponse(body: .json(.init(code: "not_found", message: "function not found")))
        return .notFound(err)
    }
}
