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

    // Parse sort string into (field, ascending) tuples
    private func parseSort(_ value: String?) -> [(String, Bool)] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: ",").map { raw in
            let token = raw.trimmingCharacters(in: .whitespaces)
            if token.hasPrefix("-") { return (String(token.dropFirst()), false) }
            if token.hasPrefix("+") { return (String(token.dropFirst()), true) }
            return (token, true)
        }
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
        var filters: [String: String] = ["corpusId": corpusId]
        if let pageId = input.query.pageId, !pageId.isEmpty { filters["pageId"] = pageId }
        let q = Query(filters: filters, sort: parseSort(input.query.sort), limit: limit, offset: offset)
        let resp = try await persistence.query(corpusId: corpusId, collection: "analyses", query: q)
        let items: [Components.Schemas.Analysis] = try resp.documents.map { data in
            let a = try JSONDecoder().decode(AnalysisRecord.self, from: data)
            return .init(value1: .init(corpusId: a.corpusId), value2: .init(analysisId: a.analysisId, pageId: a.pageId, summary: a.summary))
        }
        let payload = Operations.listAnalyses.Output.Ok.Body.jsonPayload(total: resp.total, analyses: items)
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
        let q = Query(filters: ["corpusId": corpusId], sort: parseSort(input.query.sort), limit: limit, offset: offset)
        let resp = try await persistence.query(corpusId: corpusId, collection: "baselines", query: q)
        let items: [Components.Schemas.Baseline] = try resp.documents.map { data in
            let b = try JSONDecoder().decode(Baseline.self, from: data)
            return .init(value1: .init(corpusId: b.corpusId), value2: .init(baselineId: b.baselineId, content: b.content))
        }
        let payload = Operations.listBaselines.Output.Ok.Body.jsonPayload(total: resp.total, baselines: items)
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
        var (_, functions) = try await persistence.listFunctions(corpusId: corpusId, limit: limit, offset: offset, q: q)
        // Apply optional sort locally
        let sorts = parseSort(input.query.sort)
        if let first = sorts.first {
            functions.sort { a, b in
                let asc = first.1
                switch first.0 {
                case "name": return asc ? (a.name < b.name) : (a.name > b.name)
                case "functionId": return asc ? (a.functionId < b.functionId) : (a.functionId > b.functionId)
                case "httpPath": return asc ? (a.httpPath < b.httpPath) : (a.httpPath > b.httpPath)
                default: return true
                }
            }
        }
        let items: [Components.Schemas.Function] = functions.map { f in
            .init(value1: .init(corpusId: f.corpusId),
                  value2: .init(functionId: f.functionId, name: f.name, description: f.description, httpMethod: .init(rawValue: f.httpMethod) ?? .GET, httpPath: f.httpPath))
        }
        let payload = Operations.listFunctionsInCorpus.Output.Ok.Body.jsonPayload(total: items.count, functions: items)
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
        let q = Query(filters: ["corpusId": corpusId], sort: parseSort(input.query.sort), limit: limit, offset: offset)
        let resp = try await persistence.query(corpusId: corpusId, collection: "reflections", query: q)
        let items: [Components.Schemas.Reflection] = try resp.documents.map { data in
            let r = try JSONDecoder().decode(Reflection.self, from: data)
            return .init(value1: .init(corpusId: r.corpusId), value2: .init(reflectionId: r.reflectionId, question: r.question, content: r.content))
        }
        let payload = Operations.listReflections.Output.Ok.Body.jsonPayload(total: resp.total, reflections: items)
        return .ok(.init(body: .json(payload)))
    }

    public func listFunctions(_ input: Operations.listFunctions.Input) async throws -> Operations.listFunctions.Output {
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let q = input.query.q
        var (total, functions) = try await persistence.listFunctions(limit: limit, offset: offset, q: q)
        // Apply optional sort locally
        let sorts = parseSort(input.query.sort)
        if let first = sorts.first {
            functions.sort { a, b in
                let asc = first.1
                switch first.0 {
                case "name": return asc ? (a.name < b.name) : (a.name > b.name)
                case "functionId": return asc ? (a.functionId < b.functionId) : (a.functionId > b.functionId)
                case "httpPath": return asc ? (a.httpPath < b.httpPath) : (a.httpPath > b.httpPath)
                case "corpusId": return asc ? (a.corpusId < b.corpusId) : (a.corpusId > b.corpusId)
                default: return true
                }
            }
        }
        let items: [Components.Schemas.Function] = functions.map { f in
            .init(value1: .init(corpusId: f.corpusId),
                  value2: .init(functionId: f.functionId, name: f.name, description: f.description, httpMethod: .init(rawValue: f.httpMethod) ?? .GET, httpPath: f.httpPath))
        }
        total = functions.count
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

    public func listPages(_ input: Operations.listPages.Input) async throws -> Operations.listPages.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let search = input.query.q
        var filters: [String: String] = ["corpusId": corpusId]
        if let host = input.query.host, !host.isEmpty { filters["host"] = host }

        // If q is provided, prefer server-side text search; fallback to local filter when unsupported.
        if let qstr = search, !qstr.isEmpty, qstr != "*" {
            do {
                let q = Query(filters: filters, sort: parseSort(input.query.sort), text: qstr, limit: limit, offset: offset)
                let resp = try await persistence.query(corpusId: corpusId, collection: "pages", query: q)
                let items: [Components.Schemas.Page] = try resp.documents.map { data in
                    let p = try JSONDecoder().decode(Page.self, from: data)
                    return .init(value1: .init(corpusId: p.corpusId), value2: .init(pageId: p.pageId, url: p.url, host: p.host, title: p.title))
                }
                let payload = Operations.listPages.Output.Ok.Body.jsonPayload(total: resp.total, pages: items)
                return .ok(.init(body: .json(payload)))
            } catch PersistenceError.notSupported {
                // Fallback: fetch filtered set and apply in-memory search, then sort/paginate.
                let storeQuery = Query(filters: filters)
                let resp = try await persistence.query(corpusId: corpusId, collection: "pages", query: storeQuery)
                var items: [Components.Schemas.Page] = try resp.documents.map { data in
                    let p = try JSONDecoder().decode(Page.self, from: data)
                    return .init(value1: .init(corpusId: p.corpusId), value2: .init(pageId: p.pageId, url: p.url, host: p.host, title: p.title))
                }
                let needle = qstr.lowercased()
                items = items.filter { p in
                    let v = p.value2
                    return [v.title, v.url, v.host, v.pageId].contains { $0.lowercased().contains(needle) }
                }
                if let first = parseSort(input.query.sort).first {
                    let key = first.0, asc = first.1
                    items.sort { a, b in
                        let va: String
                        let vb: String
                        switch key {
                        case "title": va = a.value2.title; vb = b.value2.title
                        case "host": va = a.value2.host; vb = b.value2.host
                        case "url": va = a.value2.url; vb = b.value2.url
                        case "pageId": va = a.value2.pageId; vb = b.value2.pageId
                        default: va = a.value2.title; vb = b.value2.title
                        }
                        return asc ? (va < vb) : (va > vb)
                    }
                }
                let total = items.count
                let slice = Array(items.dropFirst(min(offset, total)).prefix(limit))
                let payload = Operations.listPages.Output.Ok.Body.jsonPayload(total: total, pages: slice)
                return .ok(.init(body: .json(payload)))
            }
        } else {
            let q = Query(filters: filters, sort: parseSort(input.query.sort), limit: limit, offset: offset)
            let resp = try await persistence.query(corpusId: corpusId, collection: "pages", query: q)
            let items: [Components.Schemas.Page] = try resp.documents.map { data in
                let p = try JSONDecoder().decode(Page.self, from: data)
                return .init(value1: .init(corpusId: p.corpusId), value2: .init(pageId: p.pageId, url: p.url, host: p.host, title: p.title))
            }
            let total = resp.total
            let payload = Operations.listPages.Output.Ok.Body.jsonPayload(total: total, pages: items)
            return .ok(.init(body: .json(payload)))
        }
    }

    public func addPage(_ input: Operations.addPage.Input) async throws -> Operations.addPage.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let model = Page(corpusId: corpusId, pageId: req.value2.pageId, url: req.value2.url, host: req.value2.host, title: req.value2.title)
        let resp = try await persistence.addPage(model)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func listSegments(_ input: Operations.listSegments.Input) async throws -> Operations.listSegments.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let search = input.query.q
        var filters: [String: String] = ["corpusId": corpusId]
        if let kind = input.query.kind, !kind.isEmpty { filters["kind"] = kind }

        if let qstr = search, !qstr.isEmpty, qstr != "*" {
            do {
                let q = Query(filters: filters, sort: parseSort(input.query.sort), text: qstr, limit: limit, offset: offset)
                let resp = try await persistence.query(corpusId: corpusId, collection: "segments", query: q)
                let items: [Components.Schemas.Segment] = try resp.documents.map { data in
                    let s = try JSONDecoder().decode(Segment.self, from: data)
                    return .init(value1: .init(corpusId: s.corpusId), value2: .init(segmentId: s.segmentId, pageId: s.pageId, kind: s.kind, text: s.text))
                }
                let payload = Operations.listSegments.Output.Ok.Body.jsonPayload(total: resp.total, segments: items)
                return .ok(.init(body: .json(payload)))
            } catch PersistenceError.notSupported {
                let storeQuery = Query(filters: filters)
                let resp = try await persistence.query(corpusId: corpusId, collection: "segments", query: storeQuery)
                var items: [Components.Schemas.Segment] = try resp.documents.map { data in
                    let s = try JSONDecoder().decode(Segment.self, from: data)
                    return .init(value1: .init(corpusId: s.corpusId), value2: .init(segmentId: s.segmentId, pageId: s.pageId, kind: s.kind, text: s.text))
                }
                let needle = qstr.lowercased()
                items = items.filter { s in
                    let v = s.value2
                    return [v.text, v.segmentId, v.pageId].contains { $0.lowercased().contains(needle) }
                }
                if let first = parseSort(input.query.sort).first {
                    let key = first.0, asc = first.1
                    items.sort { a, b in
                        let va: String
                        let vb: String
                        switch key {
                        case "kind": va = a.value2.kind; vb = b.value2.kind
                        case "segmentId": va = a.value2.segmentId; vb = b.value2.segmentId
                        case "pageId": va = a.value2.pageId; vb = b.value2.pageId
                        default: va = a.value2.segmentId; vb = b.value2.segmentId
                        }
                        return asc ? (va < vb) : (va > vb)
                    }
                }
                let total = items.count
                let slice = Array(items.dropFirst(min(offset, total)).prefix(limit))
                let payload = Operations.listSegments.Output.Ok.Body.jsonPayload(total: total, segments: slice)
                return .ok(.init(body: .json(payload)))
            }
        } else {
            let q = Query(filters: filters, sort: parseSort(input.query.sort), limit: limit, offset: offset)
            let resp = try await persistence.query(corpusId: corpusId, collection: "segments", query: q)
            let items: [Components.Schemas.Segment] = try resp.documents.map { data in
                let s = try JSONDecoder().decode(Segment.self, from: data)
                return .init(value1: .init(corpusId: s.corpusId), value2: .init(segmentId: s.segmentId, pageId: s.pageId, kind: s.kind, text: s.text))
            }
            let total = resp.total
            let payload = Operations.listSegments.Output.Ok.Body.jsonPayload(total: total, segments: items)
            return .ok(.init(body: .json(payload)))
        }
    }

    public func addSegment(_ input: Operations.addSegment.Input) async throws -> Operations.addSegment.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let model = Segment(corpusId: corpusId, segmentId: req.value2.segmentId, pageId: req.value2.pageId, kind: req.value2.kind, text: req.value2.text)
        let resp = try await persistence.addSegment(model)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func listEntities(_ input: Operations.listEntities.Input) async throws -> Operations.listEntities.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        let search = input.query.q
        var filters: [String: String] = ["corpusId": corpusId]
        if let type = input.query._type, !type.isEmpty { filters["type"] = type }

        if let qstr = search, !qstr.isEmpty, qstr != "*" {
            do {
                let q = Query(filters: filters, sort: parseSort(input.query.sort), text: qstr, limit: limit, offset: offset)
                let resp = try await persistence.query(corpusId: corpusId, collection: "entities", query: q)
                let items: [Components.Schemas.Entity] = try resp.documents.map { data in
                    let e = try JSONDecoder().decode(Entity.self, from: data)
                    return .init(value1: .init(corpusId: e.corpusId), value2: .init(entityId: e.entityId, name: e.name, _type: e.type))
                }
                let payload = Operations.listEntities.Output.Ok.Body.jsonPayload(total: resp.total, entities: items)
                return .ok(.init(body: .json(payload)))
            } catch PersistenceError.notSupported {
                let storeQuery = Query(filters: filters)
                let resp = try await persistence.query(corpusId: corpusId, collection: "entities", query: storeQuery)
                var items: [Components.Schemas.Entity] = try resp.documents.map { data in
                    let e = try JSONDecoder().decode(Entity.self, from: data)
                    return .init(value1: .init(corpusId: e.corpusId), value2: .init(entityId: e.entityId, name: e.name, _type: e.type))
                }
                let needle = qstr.lowercased()
                items = items.filter { e in
                    let v = e.value2
                    return [v.name, v._type, v.entityId].contains { $0.lowercased().contains(needle) }
                }
                if let first = parseSort(input.query.sort).first {
                    let key = first.0, asc = first.1
                    items.sort { a, b in
                        let va: String
                        let vb: String
                        switch key {
                        case "type": va = a.value2._type; vb = b.value2._type
                        case "name": va = a.value2.name; vb = b.value2.name
                        case "entityId": va = a.value2.entityId; vb = b.value2.entityId
                        default: va = a.value2.name; vb = b.value2.name
                        }
                        return asc ? (va < vb) : (va > vb)
                    }
                }
                let total = items.count
                let slice = Array(items.dropFirst(min(offset, total)).prefix(limit))
                let payload = Operations.listEntities.Output.Ok.Body.jsonPayload(total: total, entities: slice)
                return .ok(.init(body: .json(payload)))
            }
        } else {
            let q = Query(filters: filters, sort: parseSort(input.query.sort), limit: limit, offset: offset)
            let resp = try await persistence.query(corpusId: corpusId, collection: "entities", query: q)
            let items: [Components.Schemas.Entity] = try resp.documents.map { data in
                let e = try JSONDecoder().decode(Entity.self, from: data)
                return .init(value1: .init(corpusId: e.corpusId), value2: .init(entityId: e.entityId, name: e.name, _type: e.type))
            }
            let total = resp.total
            let payload = Operations.listEntities.Output.Ok.Body.jsonPayload(total: total, entities: items)
            return .ok(.init(body: .json(payload)))
        }
    }

    public func addEntity(_ input: Operations.addEntity.Input) async throws -> Operations.addEntity.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let model = Entity(corpusId: corpusId, entityId: req.value2.entityId, name: req.value2.name, type: req.value2._type)
        let resp = try await persistence.addEntity(model)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }

    public func listTables(_ input: Operations.listTables.Input) async throws -> Operations.listTables.Output {
        let corpusId = input.path.corpusId
        let limit = input.query.limit ?? 50
        let offset = input.query.offset ?? 0
        var filters: [String: String] = ["corpusId": corpusId]
        if let pageId = input.query.pageId, !pageId.isEmpty { filters["pageId"] = pageId }
        let q = Query(filters: filters, limit: limit, offset: offset)
        let resp = try await persistence.query(corpusId: corpusId, collection: "tables", query: q)
        let items: [Components.Schemas.Table] = try resp.documents.map { data in
            let t = try JSONDecoder().decode(Table.self, from: data)
            return .init(value1: .init(corpusId: t.corpusId), value2: .init(tableId: t.tableId, pageId: t.pageId, csv: t.csv))
        }
        let payload = Operations.listTables.Output.Ok.Body.jsonPayload(total: resp.total, tables: items)
        return .ok(.init(body: .json(payload)))
    }

    public func addTable(_ input: Operations.addTable.Input) async throws -> Operations.addTable.Output {
        let corpusId = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let model = Table(corpusId: corpusId, tableId: req.value2.tableId, pageId: req.value2.pageId, csv: req.value2.csv)
        let resp = try await persistence.addTable(model)
        return .ok(.init(body: .json(.init(message: resp.message))))
    }
}
