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
        // One engine call to capture snapshot + optional CDP rects
        let raw = try await engine.snapshot(for: req.url, wait: nil, capture: nil)
        let snapshot = try await makeSnapshot(from: raw, url: req.url)
        let analysis = makeAnalysis(
            fromHTML: snapshot.rendered.html,
            text: snapshot.rendered.text,
            url: snapshot.page.uri,
            contentType: snapshot.page.contentType,
            imageId: snapshot.rendered.image?.imageId,
            rectsByBlock: raw.blockRects
        )
        // Persist visuals (best-effort)
        if let image = snapshot.rendered.image {
            let asset = SemanticMemoryService.VisualAsset(imageId: image.imageId ?? "", contentType: image.contentType ?? "image/png", width: image.width ?? 0, height: image.height ?? 0, scale: Float(image.scale ?? 1.0), fetchedAt: snapshot.page.fetchedAt)
            var anchors: [SemanticMemoryService.VisualAnchor] = []
            let anchorTs = analysis.envelope.source.fetchedAt
            for b in analysis.blocks {
                for r in (b.rects ?? []) {
                    anchors.append(SemanticMemoryService.VisualAnchor(imageId: r.imageId ?? "", x: Float(r.x ?? 0), y: Float(r.y ?? 0), w: Float(r.w ?? 0), h: Float(r.h ?? 0), excerpt: r.excerpt, confidence: Float(r.confidence ?? 0), ts: anchorTs))
                }
            }
            await service.storeVisual(pageId: analysis.envelope.id, asset: asset, anchors: anchors)
        }
        let resp = Components.Schemas.BrowseResponse(snapshot: snapshot, analysis: analysis, index: nil)
        return .ok(.init(body: .json(resp)))
    }
    public func snapshotOnly(_ input: Operations.snapshotOnly.Input) async throws -> Operations.snapshotOnly.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        let raw = try await engine.snapshot(for: req.url, wait: nil, capture: nil)
        let snapshot = try await makeSnapshot(from: raw, url: req.url)
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
        let analysis = makeAnalysis(fromHTML: html, text: text, url: url, contentType: contentType, imageId: nil, rectsByBlock: nil)
        return .ok(.init(body: .json(analysis)))
    }
    public func verifyEdition(_ input: Operations.verifyEdition.Input) async throws -> Operations.verifyEdition.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        // Resolve edition text
        var editionText: String? = nil
        if let t = req.edition.text, !t.isEmpty { editionText = t }
        if editionText == nil, let u = req.edition.url, !u.isEmpty {
            let snap = try await engine.snapshot(for: u, wait: nil, capture: nil)
            editionText = snap.text
        }
        if editionText == nil || (editionText?.isEmpty ?? true) {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        _ = req.edition.title // currently unused, reserved for reporting

        let shingleSize = req.options?.shingleSize ?? 3
        let maxExamples = req.options?.maxExamples ?? 20
        let minLineLen = req.options?.minLineLen ?? 12

        let editionTokens = TextCompare.normalizeForTokens(editionText!)
        let editionTokenSet = Set(editionTokens)
        let editionShingles = TextCompare.shingles(tokens: editionTokens, size: max(1, shingleSize))

        var results: [Components.Schemas.VerifyResult] = []
        for src in req.canonical {
            let url = src.url
            let snap = try await engine.snapshot(for: url, wait: nil, capture: nil)
            let canonicalText = snap.text
            let canonTokens = TextCompare.normalizeForTokens(canonicalText)
            let canonTokenSet = Set(canonTokens)
            let canonShingles = TextCompare.shingles(tokens: canonTokens, size: max(1, shingleSize))

            let tokenJ = TextCompare.jaccard(editionTokenSet, canonTokenSet)
            let shingleJ = TextCompare.jaccard(editionShingles, canonShingles)
            let cov = TextCompare.coverage(edition: editionText!, canonical: canonicalText, minLineLen: minLineLen)

            let examplesMissing = Array(cov.missingFromEdition.prefix(maxExamples))
            let examplesAdded = Array(cov.addedInEdition.prefix(maxExamples))

            let metrics = Components.Schemas.VerifyResult.metricsPayload(
                tokenJaccard: tokenJ,
                shingleJaccard: shingleJ,
                lineCoverage: cov.coverage,
                editionTokens: editionTokens.count,
                canonicalTokens: canonTokens.count
            )
            let examples = Components.Schemas.VerifyResult.examplesPayload(
                missingFromEdition: examplesMissing,
                addedInEdition: examplesAdded
            )
            let result = Components.Schemas.VerifyResult(
                source: .init(name: src.name, url: url),
                metrics: metrics,
                examples: examples
            )
            results.append(result)
        }

        // Pick best source by shingle Jaccard, then token Jaccard
        let best = results.max { a, b in
            let asj = a.metrics.shingleJaccard ?? 0
            let bsj = b.metrics.shingleJaccard ?? 0
            if asj == bsj { return (a.metrics.tokenJaccard ?? 0) < (b.metrics.tokenJaccard ?? 0) }
            return asj < bsj
        }
        let summary = Components.Schemas.VerifyResponse.summaryPayload(
            bestSource: best?.source.name ?? best?.source.url,
            tokenJaccardBest: best?.metrics.tokenJaccard,
            shingleJaccardBest: best?.metrics.shingleJaccard,
            lineCoverageBest: best?.metrics.lineCoverage
        )
        let body = Components.Schemas.VerifyResponse(summary: summary, results: results)
        return .ok(.init(body: .json(body)))
    }
    public func indexAnalysis(_ input: Operations.indexAnalysis.Input) async throws -> Operations.indexAnalysis.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        // Map generated Analysis -> service.FullAnalysis
        let full = fromGeneratedAnalysis(req.analysis)
        let res = await service.ingest(full: full)
        // Persist visual anchors (without asset metadata if absent)
        var anchors: [SemanticMemoryService.VisualAnchor] = []
        let anchorTs = req.analysis.envelope.source.fetchedAt
        for b in req.analysis.blocks {
            for r in (b.rects ?? []) {
                anchors.append(SemanticMemoryService.VisualAnchor(imageId: r.imageId ?? "", x: Float(r.x ?? 0), y: Float(r.y ?? 0), w: Float(r.w ?? 0), h: Float(r.h ?? 0), excerpt: r.excerpt, confidence: Float(r.confidence ?? 0), ts: anchorTs))
            }
        }
        await service.storeVisual(pageId: full.envelope.id, asset: nil, anchors: anchors)
        // Compute coverage percent
        func areaUnion(_ rects: [SemanticMemoryService.VisualAnchor]) -> Float {
            // Simple sweep over unique x; rects are normalized
            let rects = rects.map { (x: $0.x, y: $0.y, w: $0.w, h: $0.h) }.filter { $0.w > 0 && $0.h > 0 }
            let xs = Array(Set(rects.flatMap { [$0.x, $0.x + $0.w] })).sorted()
            var total: Float = 0
            for i in 0..<(max(0, xs.count - 1)) {
                let x1 = xs[i], x2 = xs[i+1]
                let w = x2 - x1; if w <= 0 { continue }
                var intervals: [(Float, Float)] = []
                for r in rects where r.x < x2 && (r.x + r.w) > x1 { intervals.append((r.y, r.y + r.h)) }
                if intervals.isEmpty { continue }
                intervals.sort { $0.0 < $1.0 }
                var covered: Float = 0
                var cur = intervals[0]
                for seg in intervals.dropFirst() {
                    if seg.0 <= cur.1 { cur.1 = max(cur.1, seg.1) }
                    else { covered += max(0, cur.1 - cur.0); cur = seg }
                }
                covered += max(0, cur.1 - cur.0)
                total += w * covered
            }
            return max(0, min(1, total))
        }
        let coverage = areaUnion(anchors)
        let out = Components.Schemas.IndexResult(
            pagesUpserted: res.pagesUpserted,
            segmentsUpserted: res.segmentsUpserted,
            entitiesUpserted: res.entitiesUpserted,
            tablesUpserted: res.tablesUpserted,
            anchorsPersisted: anchors.count,
            coveragePercent: Double(coverage)
        )
        return .ok(.init(body: .json(out)))
    }
    public func reindexRegion(_ input: Operations.reindexRegion.Input) async throws -> Operations.reindexRegion.Output {
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload())
        }
        // Resolve URL either from pageId or direct field
        let url: String
        if let pid = req.pageId, !pid.isEmpty, let page = await service.getPage(id: pid) { url = page.url }
        else if let u = req.url, !u.isEmpty { url = u }
        else { return .undocumented(statusCode: 400, OpenAPIRuntime.UndocumentedPayload()) }

        // Snapshot + analysis with rects when available
        let raw = try await engine.snapshot(for: url, wait: nil, capture: nil)
        let snapshot = try await makeSnapshot(from: raw, url: url)
        let analysisFull = makeAnalysis(
            fromHTML: snapshot.rendered.html,
            text: snapshot.rendered.text,
            url: snapshot.page.uri,
            contentType: snapshot.page.contentType,
            imageId: snapshot.rendered.image?.imageId,
            rectsByBlock: raw.blockRects
        )
        // Filter blocks by intersection with region
        let region = req.region
        func intersects(_ b: Components.Schemas.Block.rectsPayload?) -> Bool {
            guard let rs = b else { return false }
            for r in rs {
                let x1 = r.x ?? 0, y1 = r.y ?? 0, w1 = r.w ?? 0, h1 = r.h ?? 0
                let x2 = region.x, y2 = region.y, w2 = region.w, h2 = region.h
                if x1 < x2 + w2 && x1 + w1 > x2 && y1 < y2 + h2 && y1 + h1 > y2 { return true }
            }
            return false
        }
        let filteredBlocks = analysisFull.blocks.filter { intersects($0.rects) }
        let filtered = Components.Schemas.Analysis(
            envelope: analysisFull.envelope,
            blocks: filteredBlocks,
            semantics: analysisFull.semantics,
            summaries: analysisFull.summaries,
            provenance: analysisFull.provenance
        )
        // Map to FullAnalysis and ingest
        let full = fromGeneratedAnalysis(filtered)
        let res = await service.ingest(full: full)
        // Persist visual anchors for region (best-effort)
        var anchors: [SemanticMemoryService.VisualAnchor] = []
        for b in filtered.blocks {
            for r in (b.rects ?? []) {
                anchors.append(SemanticMemoryService.VisualAnchor(imageId: r.imageId ?? "", x: Float(r.x ?? 0), y: Float(r.y ?? 0), w: Float(r.w ?? 0), h: Float(r.h ?? 0), excerpt: r.excerpt, confidence: Float(r.confidence ?? 0), ts: filtered.envelope.source.fetchedAt))
            }
        }
        await service.storeVisual(pageId: filtered.envelope.id, asset: snapshot.rendered.image.map { SemanticMemoryService.VisualAsset(imageId: $0.imageId ?? "", contentType: $0.contentType ?? "image/png", width: $0.width ?? 0, height: $0.height ?? 0, scale: Float($0.scale ?? 1.0), fetchedAt: snapshot.page.fetchedAt) }, anchors: anchors)
        // Compute coverage of region
        func areaUnion(_ rects: [SemanticMemoryService.VisualAnchor]) -> Float { let xs = Array(Set(rects.flatMap { [$0.x, $0.x + $0.w] })).sorted(); var total: Float = 0; for i in 0..<(max(0, xs.count - 1)) { let x1 = xs[i], x2 = xs[i+1], w = x2-x1; if w<=0 { continue }; var iv: [(Float,Float)] = []; for r in rects where r.x < x2 && (r.x + r.w) > x1 { iv.append((r.y, r.y + r.h)) }; if iv.isEmpty { continue }; iv.sort { $0.0 < $1.0 }; var covered: Float = 0; var cur = iv[0]; for s in iv.dropFirst() { if s.0 <= cur.1 { cur.1 = max(cur.1, s.1) } else { covered += max(0, cur.1 - cur.0); cur = s } }; covered += max(0, cur.1 - cur.0); total += w * covered }; return max(0, min(1, total)) }
        let cov = areaUnion(anchors)
        let out = Components.Schemas.IndexResult(
            pagesUpserted: res.pagesUpserted,
            segmentsUpserted: res.segmentsUpserted,
            entitiesUpserted: res.entitiesUpserted,
            tablesUpserted: res.tablesUpserted,
            anchorsPersisted: anchors.count,
            coveragePercent: Double(cov)
        )
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
    public func exportArtifacts(_ input: Operations.exportArtifacts.Input) async throws -> Operations.exportArtifacts.Output {
        let pageId = input.query.pageId
        switch input.query.format {
        case .snapshot_period_html:
            if let s = await resolveSnapshot(pageId: pageId) {
                return .ok(.init(body: .html(HTTPBody(s.rendered.html))))
            }
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        case .snapshot_period_text:
            if let s = await resolveSnapshot(pageId: pageId) {
                return .ok(.init(body: .plainText(HTTPBody(s.rendered.text))))
            }
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        case .analysis_period_json:
            let primary = await resolveAnalysis(pageId: pageId)
            let fallback = await fallbackAnalysisFromSnapshot(pageId: pageId)
            if let analysis = primary ?? fallback {
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                if let data = try? enc.encode(analysis),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sendable = asSendableJSON(obj) as? [String: (any Sendable)?],
                   let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: sendable) {
                    return .ok(.init(body: .json(container)))
                }
            }
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        case .summary_period_md:
            if let s = await resolveSnapshot(pageId: pageId) {
                let text = s.rendered.text
                let title = text.split(separator: "\n").first.map(String.init) ?? "Summary"
                let abstract = String(text.prefix(1000))
                let md = "# \(title)\n\n\(abstract)\n"
                return .ok(.init(body: .text_markdown(HTTPBody(md))))
            }
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        case .tables_period_csv:
            let primary = await resolveAnalysis(pageId: pageId)
            let fallback = await fallbackAnalysisFromSnapshot(pageId: pageId)
            if let analysis = primary ?? fallback {
                // Pick first table from blocks
                if let table = analysis.blocks.compactMap({ $0.table }).first {
                    let header = (table.columns ?? []).joined(separator: ",")
                    let rows = table.rows.map { $0.map { $0.replacingOccurrences(of: ",", with: " ") }.joined(separator: ",") }
                    let csv = ([header] + rows).joined(separator: "\n")
                    return .ok(.init(body: .csv(HTTPBody(csv))))
                }
                return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
            }
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        }
    }

    // MARK: - Mapping helpers
    private func fromGeneratedAnalysis(_ a: Components.Schemas.Analysis) -> SemanticMemoryService.FullAnalysis {
        let envelope = SemanticMemoryService.FullAnalysis.Envelope(
            id: a.envelope.id,
            source: .init(uri: a.envelope.source.uri),
            contentType: a.envelope.contentType,
            language: a.envelope.language
        )
        let blocks: [SemanticMemoryService.FullAnalysis.Block] = a.blocks.map {
            let table = $0.table.map { SemanticMemoryService.FullAnalysis.Table(caption: $0.caption, columns: $0.columns, rows: $0.rows) }
            return .init(id: $0.id, kind: $0.kind.rawValue, text: $0.text, table: table)
        }
        let ents: [SemanticMemoryService.FullAnalysis.Semantics.Entity]? = a.semantics?.entities?.map { e in
            .init(id: e.id, name: e.name, type: e._type.rawValue)
        }
        let semantics = SemanticMemoryService.FullAnalysis.Semantics(entities: ents)
        return .init(envelope: envelope, blocks: blocks, semantics: semantics)
    }

    private func resolveSnapshot(pageId: String) async -> Components.Schemas.Snapshot? {
        if let s = await service.resolveSnapshot(byPageId: pageId) {
            // Rehydrate to API schema
            let page = Components.Schemas.Snapshot.pagePayload(
                uri: s.url, finalUrl: s.url, fetchedAt: Date(), status: 200, contentType: "text/html"
            )
            let rendered = Components.Schemas.Snapshot.renderedPayload(html: s.renderedHTML, text: s.renderedText)
            return .init(snapshotId: s.id, page: page, rendered: rendered)
        }
        return nil
    }

    private func resolveAnalysis(pageId: String) async -> Components.Schemas.Analysis? {
        if let a = await service.resolveAnalysis(byPageId: pageId) {
            // Map service.FullAnalysis -> generated schema
            let blocks: [Components.Schemas.Block] = a.blocks.map { b in
                Components.Schemas.Block(
                    id: b.id,
                    kind: .init(rawValue: b.kind) ?? .paragraph,
                    text: b.text,
                    table: b.table.map { Components.Schemas.Table(caption: $0.caption, columns: $0.columns, rows: $0.rows) }
                )
            }
            let env = Components.Schemas.Analysis.envelopePayload(
                id: a.envelope.id,
                source: .init(uri: a.envelope.source?.uri, fetchedAt: nil),
                contentType: a.envelope.contentType ?? "text/html",
                language: a.envelope.language ?? "en"
            )
            let summaries = Components.Schemas.Analysis.summariesPayload(abstract: nil, keyPoints: nil, tl_semi_dr: nil)
            let prov = Components.Schemas.Analysis.provenancePayload(pipeline: "stored", model: nil)
            let ents = a.semantics?.entities?.map { Components.Schemas.Entity(id: $0.id, name: $0.name, _type: .init(rawValue: $0.type) ?? .OTHER, mentions: []) }
            let sem = Components.Schemas.Analysis.semanticsPayload(outline: nil, entities: ents, claims: nil)
            return .init(envelope: env, blocks: blocks, semantics: sem, summaries: summaries, provenance: prov)
        }
        return nil
    }

    private func fallbackAnalysisFromSnapshot(pageId: String) async -> Components.Schemas.Analysis? {
        guard let s = await resolveSnapshot(pageId: pageId) else { return nil }
        return makeAnalysis(fromHTML: s.rendered.html, text: s.rendered.text, url: s.page.finalUrl ?? s.page.uri, contentType: s.page.contentType, imageId: nil, rectsByBlock: nil)
    }

    // Convert JSONSerialization trees into Sendable JSON compatible trees.
    private func asSendableJSON(_ value: Any?) -> (any Sendable)? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let v = value as? String { return v }
        if let v = value as? Int { return v }
        if let v = value as? Double { return v }
        if let v = value as? Bool { return v }
        if let v = value as? [Any] {
            return v.map { asSendableJSON($0) }
        }
        if let v = value as? [String: Any] {
            var out: [String: (any Sendable)?] = [:]
            for (k, val) in v {
                out[k] = asSendableJSON(val)
            }
            return out
        }
        // Fallback: stringify
        return String(describing: value)
    }

    // MARK: - Helpers
    private func makeSnapshot(from r: SnapshotResult, url: String) async throws -> Components.Schemas.Snapshot {
        let page = Components.Schemas.Snapshot.pagePayload(
            uri: url,
            finalUrl: r.finalURL,
            fetchedAt: Date(),
            status: r.pageStatus ?? 200,
            contentType: r.pageContentType ?? "text/html",
            navigation: .init(ttfbMs: nil, loadMs: r.loadMs)
        )
        // Attach image metadata and persist asset if available
        let image: Components.Schemas.Snapshot.renderedPayload.imagePayload? = await {
            guard let png = r.screenshotPNG, let w = r.screenshotWidth, let h = r.screenshotHeight else { return nil }
            let id = UUID().uuidString
            // Persist dev asset to disk path
            if let path = try? persistImageAsset(imageId: id, data: png) {
                await service.storeArtifactRef(ownerId: id, kind: "image/png", refPath: path)
            }
            return .init(imageId: id, contentType: "image/png", width: w, height: h, scale: r.screenshotScale ?? 1.0)
        }()
        let rendered = Components.Schemas.Snapshot.renderedPayload(html: r.html, text: r.text, image: image, meta: nil)
        let requests: [Components.Schemas.Snapshot.networkPayload.requestsPayloadPayload]? = r.network?.map { req in
            Components.Schemas.Snapshot.networkPayload.requestsPayloadPayload(
                url: req.url,
                _type: .init(from: req.type),
                status: req.status,
                body: req.body
            )
        }
        let network = requests.map { Components.Schemas.Snapshot.networkPayload(requests: $0) }
        let snapshot = Components.Schemas.Snapshot(
            snapshotId: UUID().uuidString,
            page: page,
            rendered: rendered,
            network: network,
            diagnostics: nil
        )
        let keep = SemanticMemoryService.Snapshot(id: snapshot.snapshotId, url: snapshot.page.uri, renderedHTML: r.html, renderedText: r.text)
        await service.store(snapshot: keep)
        return snapshot
    }

    // Dev-only asset persistence to a predictable local folder
    private func persistImageAsset(imageId: String, data: Data) throws -> String {
        let env = ProcessInfo.processInfo.environment
        let base = env["SB_ASSET_DIR"] ?? (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".fountain", isDirectory: true).appendingPathComponent("semantic-browser", isDirectory: true).path)
        let dirURL = URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL = dirURL.appendingPathComponent("\(imageId).png", isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    private func makeAnalysis(fromHTML html: String, text: String, url: String, contentType: String, imageId: String?, rectsByBlock: [String: [NormalizedRect]]?) -> Components.Schemas.Analysis {
        let spans = parser.parseTextAndBlocks(from: html).1
        // Synthetic rects: distribute normalized bands by block index to provide a visual anchor fallback
        func syntheticRects(total: Int, index: Int, text: String) -> Components.Schemas.Block.rectsPayload {
            let pad: Float = 0.02
            let bandH: Float = (1.0 - pad * Float(total + 1)) / Float(max(1, total))
            let y: Float = pad + Float(index) * (bandH + pad)
            let rect = Components.Schemas.Block.rectsPayloadPayload(
                imageId: "synthetic",
                x: 0.05,
                y: y,
                w: 0.90,
                h: max(0.04, bandH * 0.8),
                excerpt: String(text.prefix(120)),
                confidence: 0.5
            )
            return [rect]
        }
        let total = spans.count
        let blocks: [Components.Schemas.Block] = spans.enumerated().map { idx, s in
            let synthetic = syntheticRects(total: total, index: idx, text: s.text)
            let real: Components.Schemas.Block.rectsPayload? = {
                guard let imageId, let rectsByBlock, let rs = rectsByBlock[s.id], !rs.isEmpty else { return nil }
                return rs.map { r in
                    Components.Schemas.Block.rectsPayloadPayload(
                        imageId: imageId,
                        x: r.x,
                        y: r.y,
                        w: r.w,
                        h: r.h,
                        excerpt: r.excerpt ?? String(s.text.prefix(120)),
                        confidence: r.confidence ?? 0.9
                    )
                }
            }()
            return Components.Schemas.Block(
                id: s.id,
                kind: Components.Schemas.Block.kindPayload(rawValue: s.kind) ?? .paragraph,
                level: s.level,
                text: s.text,
                rects: real ?? synthetic,
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

// MARK: - Visuals Query
extension SemanticBrowserOpenAPI {
    public func getVisual(_ input: Operations.getVisual.Input) async throws -> Operations.getVisual.Output {
        let pageId = input.query.pageId
        if let (asset, anchors) = await service.loadVisual(pageId: pageId) {
            let image: Components.Schemas.VisualResponse.imagePayload?
            if let a = asset {
                image = .init(imageId: a.imageId, contentType: a.contentType, width: a.width, height: a.height, scale: Float(a.scale), fetchedAt: a.fetchedAt)
            } else { image = nil }
            var rects: [Components.Schemas.VisualResponse.anchorsPayloadPayload] = []
            let threshDays = input.query.staleThresholdDays
            var cutoff: Date? = nil
            if let days = threshDays, let fetched = asset?.fetchedAt { cutoff = Calendar.current.date(byAdding: .day, value: -max(1, days), to: fetched) }
            // Optional coverage classification via token overlap of anchor.excerpt vs stored segment texts for the page
            let classify = input.query.classify ?? false
            var segTexts: [String] = []
            if classify { segTexts = await service.segmentTextsForPage(pageId: pageId) }
            for r in anchors {
                let stale: Bool? = {
                    guard let c = cutoff, let ts = r.ts else { return nil }
                    return ts < c
                }()
                let covered: Bool? = {
                    guard classify, let excerpt = r.excerpt, !excerpt.isEmpty else { return nil }
                    func bag(_ s: String) -> [String: Int] {
                        let tokens = s.lowercased().replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression).split(separator: " ").map(String.init).filter { $0.count >= 3 }
                        var b: [String: Int] = [:]; for t in tokens { b[t, default: 0] += 1 }; return b
                    }
                    func jacc(_ a: [String:Int], _ b: [String:Int]) -> Double { let keys = Set(a.keys).union(b.keys); var inter=0.0, uni=0.0; for k in keys { let av=Double(a[k] ?? 0), bv=Double(b[k] ?? 0); inter += min(av,bv); uni += max(av,bv) }; return uni == 0 ? 0 : inter/uni }
                    let eb = bag(excerpt)
                    let maxJ = segTexts.map { jacc(eb, bag($0)) }.max() ?? 0
                    return maxJ >= 0.18
                }()
                let rr = Components.Schemas.VisualResponse.anchorsPayloadPayload(
                    imageId: r.imageId,
                    x: r.x,
                    y: r.y,
                    w: r.w,
                    h: r.h,
                    excerpt: r.excerpt,
                    confidence: r.confidence,
                    ts: r.ts.map { Int($0.timeIntervalSince1970 * 1000.0) },
                    stale: stale,
                    covered: covered
                )
                rects.append(rr)
            }
            let body = Components.Schemas.VisualResponse(image: image, anchors: rects)
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
    }
}
