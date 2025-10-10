import Foundation
import OpenAPIRuntime

public struct SemanticBrowserOpenAPI: APIProtocol, @unchecked Sendable {
    let service: SemanticMemoryService

    public init(service: SemanticMemoryService) { self.service = service }

    public func health(_ input: Operations.health.Input) async throws -> Operations.health.Output {
        let pool = Operations.health.Output.Ok.Body.jsonPayload.browserPoolPayload(capacity: 0, inUse: 0)
        let body = Operations.health.Output.Ok.Body.jsonPayload(status: .ok, version: "0.1", browserPool: pool)
        return .ok(.init(body: .json(body)))
    }

    public func queryPages(_ input: Operations.queryPages.Input) async throws -> Operations.queryPages.Output {
        let q = input.query.q
        let host = input.query.host
        let lang = input.query.lang
        let limit = input.query.limit ?? 20
        let offset = input.query.offset ?? 0
        let (total, items) = await service.queryPages(q: q, host: host, lang: lang, limit: limit, offset: offset)
        let mapped: [Components.Schemas.PageDoc] = items.map { p in
            Components.Schemas.PageDoc(
                id: p.id,
                url: p.url,
                host: p.host,
                status: p.status,
                contentType: p.contentType,
                lang: p.lang,
                title: p.title,
                textSize: p.textSize,
                fetchedAt: p.fetchedAt,
                labels: p.labels
            )
        }
        let payload = Operations.queryPages.Output.Ok.Body.jsonPayload(total: total, items: mapped)
        return .ok(.init(body: .json(payload)))
    }

    public func querySegments(_ input: Operations.querySegments.Input) async throws -> Operations.querySegments.Output {
        let q = input.query.q
        let kind = input.query.kind?.rawValue
        let entity = input.query.entity
        let limit = input.query.limit ?? 20
        let offset = input.query.offset ?? 0
        let (total, items) = await service.querySegments(q: q, kind: kind, entity: entity, limit: limit, offset: offset)
        let mapped: [Components.Schemas.SegmentDoc] = items.map { s in
            Components.Schemas.SegmentDoc(
                id: s.id,
                pageId: s.pageId,
                kind: Components.Schemas.SegmentDoc.kindPayload(rawValue: s.kind),
                text: s.text,
                pathHint: s.pathHint,
                offsetStart: s.offsetStart,
                offsetEnd: s.offsetEnd,
                entities: s.entities
            )
        }
        let payload = Operations.querySegments.Output.Ok.Body.jsonPayload(total: total, items: mapped)
        return .ok(.init(body: .json(payload)))
    }

    public func queryEntities(_ input: Operations.queryEntities.Input) async throws -> Operations.queryEntities.Output {
        let q = input.query.q
        let type = input.query._type?.rawValue
        let limit = input.query.limit ?? 20
        let offset = input.query.offset ?? 0
        let (total, items) = await service.queryEntities(q: q, type: type, limit: limit, offset: offset)
        let mapped: [Components.Schemas.EntityDoc] = items.map { e in
            Components.Schemas.EntityDoc(id: e.id, name: e.name, _type: e.type, pageCount: e.pageCount, mentions: e.mentions)
        }
        let payload = Operations.queryEntities.Output.Ok.Body.jsonPayload(total: total, items: mapped)
        return .ok(.init(body: .json(payload)))
    }

    // Unimplemented endpoints: return 501 for now to keep wiring minimal.
    public func browseAndDissect(_ input: Operations.browseAndDissect.Input) async throws -> Operations.browseAndDissect.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }
    public func snapshotOnly(_ input: Operations.snapshotOnly.Input) async throws -> Operations.snapshotOnly.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }
    public func analyzeSnapshot(_ input: Operations.analyzeSnapshot.Input) async throws -> Operations.analyzeSnapshot.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }
    public func indexAnalysis(_ input: Operations.indexAnalysis.Input) async throws -> Operations.indexAnalysis.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }
    public func getPage(_ input: Operations.getPage.Input) async throws -> Operations.getPage.Output {
        .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
    }
    public func exportArtifacts(_ input: Operations.exportArtifacts.Input) async throws -> Operations.exportArtifacts.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }
}
