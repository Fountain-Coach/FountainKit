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

    public func createCorpus(_ input: Operations.createCorpus.Input) async throws -> Operations.createCorpus.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let resp = try await persistence.createCorpus(.init(corpusId: req.corpusId))
        return .created(.init(body: .json(.init(corpusId: resp.corpusId, message: resp.message))))
    }
}

