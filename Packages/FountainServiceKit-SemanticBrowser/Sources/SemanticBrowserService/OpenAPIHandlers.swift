import Foundation
import OpenAPIRuntime

private extension Components.Schemas.Snapshot.networkPayload.requestsPayloadPayload._typePayload {
    init?(from s: String?) {
        guard let s else { return nil }
        self.init(rawValue: s)
    }
}

public struct SemanticBrowserOpenAPI: APIProtocol, @unchecked Sendable {
    let service: SemanticMemoryService
    let engine: BrowserEngine
    let parser: HTMLParser

    public init(service: SemanticMemoryService, engine: BrowserEngine, parser: HTMLParser = HTMLParser()) {
        self.service = service
        self.engine = engine
        self.parser = parser
    }

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

    public func browseAndDissect(_ input: Operations.browseAndDissect.Input) async throws -> Operations.browseAndDissect.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        let snapshot = try await makeSnapshot(url: req.url)
        let analysis = makeAnalysis(fromHTML: snapshot.rendered.html, text: snapshot.rendered.text, url: snapshot.page.uri, contentType: snapshot.page.contentType)
        let resp = Components.Schemas.BrowseResponse(snapshot: snapshot, analysis: analysis, index: nil)
        return .ok(.init(body: .json(resp)))
    }
    public func snapshotOnly(_ input: Operations.snapshotOnly.Input) async throws -> Operations.snapshotOnly.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        let snapshot = try await makeSnapshot(url: req.url)
        return .ok(.init(body: .json(.init(snapshot: snapshot))))
    }
    public func analyzeSnapshot(_ input: Operations.analyzeSnapshot.Input) async throws -> Operations.analyzeSnapshot.Output {
        let html: String
        let text: String
        let url: String
        let contentType = "text/html"
        if case let .json(req) = input.body, let s = req.snapshot {
            html = s.rendered.html
            text = s.rendered.text
            url = s.page.finalUrl ?? s.page.uri
        } else if case let .json(req) = input.body, let sid = req.snapshotRef?.snapshotId, let stored = await service.loadSnapshot(id: sid) {
            html = stored.renderedHTML
            text = stored.renderedText
            url = stored.url
        } else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        let analysis = makeAnalysis(fromHTML: html, text: text, url: url, contentType: contentType)
        return .ok(.init(body: .json(analysis)))
    }
    public func indexAnalysis(_ input: Operations.indexAnalysis.Input) async throws -> Operations.indexAnalysis.Output {
        let out = Components.Schemas.IndexResult(pagesUpserted: 0, segmentsUpserted: 0, entitiesUpserted: 0, tablesUpserted: 0)
        return .ok(.init(body: .json(out)))
    }
    public func getPage(_ input: Operations.getPage.Input) async throws -> Operations.getPage.Output {
        let id = input.path.id
        if let p = await service.getPage(id: id) {
            let model = Components.Schemas.PageDoc(id: p.id, url: p.url, host: p.host, status: p.status, contentType: p.contentType, lang: p.lang, title: p.title, textSize: p.textSize, fetchedAt: p.fetchedAt, labels: p.labels)
            return .ok(.init(body: .json(model)))
        }
        return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
    }
    public func exportArtifacts(_ input: Operations.exportArtifacts.Input) async throws -> Operations.exportArtifacts.Output { .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload()) }

    // MARK: - Helpers
    private func makeSnapshot(url: String) async throws -> Components.Schemas.Snapshot {
        let r = try await engine.snapshot(for: url, wait: nil, capture: nil)
        let page = Components.Schemas.Snapshot.pagePayload(
            uri: url,
            finalUrl: r.finalURL,
            fetchedAt: Date(),
            status: r.pageStatus ?? 200,
            contentType: r.pageContentType ?? "text/html",
            navigation: .init(ttfbMs: nil, loadMs: r.loadMs)
        )
        let rendered = Components.Schemas.Snapshot.renderedPayload(html: r.html, text: r.text)
        let requests: [Components.Schemas.Snapshot.networkPayload.requestsPayloadPayload]? = r.network?.map { req in
            .init(url: req.url, _type: .init(from: req.type), status: req.status, body: req.body)
        }
        let network = requests.map { Components.Schemas.Snapshot.networkPayload(requests: $0) }
        let snapshot = Components.Schemas.Snapshot(
            snapshotId: UUID().uuidString,
            page: page,
            rendered: rendered,
            network: network,
            diagnostics: nil
        )
        await service.store(snapshot: .init(id: snapshot.snapshotId, url: snapshot.page.uri, renderedHTML: r.html, renderedText: r.text))
        return snapshot
    }

    private func makeAnalysis(fromHTML html: String, text: String, url: String, contentType: String) -> Components.Schemas.Analysis {
        let spans = parser.parseTextAndBlocks(from: html).1
        let blocks: [Components.Schemas.Block] = spans.map { s in
            Components.Schemas.Block(
                id: s.id,
                kind: Components.Schemas.Block.kindPayload(rawValue: s.kind) ?? .paragraph,
                level: s.level,
                text: s.text,
                span: [s.start, s.end],
                table: s.table.map { Components.Schemas.Table(caption: $0.caption, columns: $0.columns, rows: $0.rows) }
            )
        }
        let outline = blocks.compactMap { b -> Components.Schemas.Analysis.semanticsPayload.outlinePayloadPayload? in
            guard b.kind == .heading else { return nil }
            return .init(block: b.id, level: b.level)
        }
        let semantics = Components.Schemas.Analysis.semanticsPayload(outline: outline.isEmpty ? nil : outline, entities: nil, claims: nil)
        let envelope = Components.Schemas.Analysis.envelopePayload(
            id: UUID().uuidString,
            source: .init(uri: url, fetchedAt: Date()),
            contentType: contentType,
            language: Locale.current.language.languageCode?.identifier ?? "en",
            bytes: (html.utf8.count + text.utf8.count),
            diagnostics: nil
        )
        let summaries = Components.Schemas.Analysis.summariesPayload(abstract: String(text.prefix(280)), keyPoints: nil, tl_semi_dr: nil)
        let provenance = Components.Schemas.Analysis.provenancePayload(pipeline: "html-parser", model: nil)
        return Components.Schemas.Analysis(envelope: envelope, blocks: blocks, semantics: semantics, summaries: summaries, provenance: provenance)
    }
}
