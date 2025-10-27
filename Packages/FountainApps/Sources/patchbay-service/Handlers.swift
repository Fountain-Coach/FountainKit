import Foundation
import OpenAPIRuntime
import FountainStoreClient
import SecretStore

// Minimal in-memory store using generated schema types
final class PatchBayCore: @unchecked Sendable {
    var canvas: Components.Schemas.CanvasState
    var instruments: [String: Components.Schemas.Instrument] = [:]
    var links: [String: Components.Schemas.Link] = [:]
    // discovered endpoints cache (optional)
    init() {
        self.canvas = .init(
            docWidth: 1200,
            docHeight: 800,
            gridStep: 24,
            autoScale: true,
            theme: .light,
            transform: .init(scale: 1.0, translation: .init(x: 0, y: 0))
        )
        // Seed only an AudioTalk Chat instrument as default
        if let chatKind = Components.Schemas.InstrumentKind(rawValue: "audiotalk.chat") {
            let chat = InstrumentProviders.makeInstrument(id: "chat_1", kind: chatKind, title: "AudioTalk Chat", x: 360, y: 160, w: 300, h: 180)
            instruments[chat.id] = chat
        }
    }
}

final class PatchBayHandlers: APIProtocol, @unchecked Sendable {
    let core = PatchBayCore()
    let store: FountainStoreClient
    let corpusId: String
    let secrets: any SecretStore

    init(env: [String: String] = ProcessInfo.processInfo.environment) {
        self.corpusId = env["PATCHBAY_CORPUS"] ?? "patchbay"
        self.store = Self.resolveStore(from: env)
        self.secrets = KeychainStore(service: "FountainAI.PatchBay")
    }

    private static func resolveStore(from env: [String: String]) -> FountainStoreClient {
        let root: URL
        if let override = env["FOUNTAINSTORE_DIR"], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if override.hasPrefix("~") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                root = URL(fileURLWithPath: home + String(override.dropFirst()), isDirectory: true)
            } else {
                root = URL(fileURLWithPath: override, isDirectory: true)
            }
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            root = cwd.appendingPathComponent(".fountain/store", isDirectory: true)
        }
        do {
            let disk = try DiskFountainStoreClient(rootDirectory: root)
            return FountainStoreClient(client: disk)
        } catch {
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }
    }

    // Health
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output { .ok(.init(body: .json(.init(status: .ok)))) }

    // Canvas
    func getCanvas(_ input: Operations.getCanvas.Input) async throws -> Operations.getCanvas.Output { .ok(.init(body: .json(core.canvas))) }
    func patchCanvas(_ input: Operations.patchCanvas.Input) async throws -> Operations.patchCanvas.Output {
        if case let .json(patch) = input.body {
            if let g = patch.gridStep { core.canvas.gridStep = g }
            if let a = patch.autoScale { core.canvas.autoScale = a }
            if let t = patch.theme { core.canvas.theme = .init(rawValue: t.rawValue) }
        }
        return .ok(.init(body: .json(core.canvas)))
    }
    func zoomFit(_ input: Operations.zoomFit.Input) async throws -> Operations.zoomFit.Output { core.canvas.transform = .init(scale: 1.0, translation: .init(x: 0, y: 0)); return .noContent }
    func zoomActual(_ input: Operations.zoomActual.Input) async throws -> Operations.zoomActual.Output { core.canvas.transform.scale = 1.0; return .noContent }
    func zoomSet(_ input: Operations.zoomSet.Input) async throws -> Operations.zoomSet.Output { if case let .json(b) = input.body { core.canvas.transform.scale = max(0.1, min(16.0, b.scale)) }; return .noContent }
    func panBy(_ input: Operations.panBy.Input) async throws -> Operations.panBy.Output { if case let .json(b) = input.body { core.canvas.transform.translation.x += b.dx; core.canvas.transform.translation.y += b.dy }; return .noContent }

    // Graph
    func getGraph(_ input: Operations.getGraph.Input) async throws -> Operations.getGraph.Output {
        let gTheme = Components.Schemas.GraphDoc.canvasPayload.themePayload(rawValue: (core.canvas.theme?.rawValue) ?? "light") ?? .light
        let doc = Components.Schemas.GraphDoc(
            canvas: .init(width: core.canvas.docWidth, height: core.canvas.docHeight, theme: gTheme, grid: core.canvas.gridStep),
            instruments: Array(core.instruments.values),
            links: Array(core.links.values),
            notes: []
        )
        return .ok(.init(body: .json(doc)))
    }
    func putGraph(_ input: Operations.putGraph.Input) async throws -> Operations.putGraph.Output {
        guard case let .json(doc) = input.body else { return .undocumented(statusCode: 400, .init()) }
        core.canvas.docWidth = doc.canvas.width
        core.canvas.docHeight = doc.canvas.height
        core.canvas.gridStep = doc.canvas.grid
        core.canvas.theme = .init(rawValue: doc.canvas.theme.rawValue)
        core.instruments = Dictionary(uniqueKeysWithValues: doc.instruments.map { ($0.id, $0) })
        core.links = Dictionary(uniqueKeysWithValues: doc.links.map { ($0.id, $0) })
        return .noContent
    }

    // Instruments
    func listInstruments(_ input: Operations.listInstruments.Input) async throws -> Operations.listInstruments.Output { .ok(.init(body: .json(Array(core.instruments.values)))) }
    func createInstrument(_ input: Operations.createInstrument.Input) async throws -> Operations.createInstrument.Output {
        guard case let .json(body) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let id = body.id
        let inst = InstrumentProviders.makeInstrument(id: id, kind: body.kind, title: body.title, x: body.x, y: body.y, w: body.w, h: body.h)
        core.instruments[id] = inst
        return .created(.init(body: .json(inst)))
    }
    func getInstrument(_ input: Operations.getInstrument.Input) async throws -> Operations.getInstrument.Output { guard let i = core.instruments[input.path.id] else { return .undocumented(statusCode: 404, .init()) }; return .ok(.init(body: .json(i))) }
    func patchInstrument(_ input: Operations.patchInstrument.Input) async throws -> Operations.patchInstrument.Output {
        let id = input.path.id
        guard var i = core.instruments[id], case let .json(p) = input.body else { return .undocumented(statusCode: 404, .init()) }
        if let t = p.title { i.title = t }
        if let v = p.x { i.x = v }
        if let v = p.y { i.y = v }
        if let v = p.w { i.w = v }
        if let v = p.h { i.h = v }
        if let d = p.propertyDefaults {
            // Convert PatchInstrument defaults to Instrument defaults
            let converted = Components.Schemas.Instrument.propertyDefaultsPayload(
                additionalProperties: d.additionalProperties.mapValues { v in
                    switch v {
                    case .case1(let x): return .case1(x)
                    case .case2(let x): return .case2(x)
                    case .case3(let x): return .case3(x)
                    case .case4(let x): return .case4(x)
                    }
                }
            )
            i.propertyDefaults = converted
        }
        core.instruments[id] = i
        return .ok(.init(body: .json(i)))
    }
    func deleteInstrument(_ input: Operations.deleteInstrument.Input) async throws -> Operations.deleteInstrument.Output { core.instruments.removeValue(forKey: input.path.id); return .noContent }
    func getInstrumentSchema(_ input: Operations.getInstrumentSchema.Input) async throws -> Operations.getInstrumentSchema.Output { guard let i = core.instruments[input.path.id] else { return .undocumented(statusCode: 404, .init()) }; return .ok(.init(body: .json(i.propertySchema))) }

    // Links
    func listLinks(_ input: Operations.listLinks.Input) async throws -> Operations.listLinks.Output { .ok(.init(body: .json(Array(core.links.values)))) }
    func createLink(_ input: Operations.createLink.Input) async throws -> Operations.createLink.Output {
        guard case let .json(body) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let id = UUID().uuidString
        let lkind = Components.Schemas.Link.kindPayload(rawValue: body.kind.rawValue) ?? .property
        let link = Components.Schemas.Link(id: id, kind: lkind, property: body.property, ump: body.ump)
        core.links[id] = link
        return .created(.init(body: .json(link)))
    }
    func deleteLink(_ input: Operations.deleteLink.Input) async throws -> Operations.deleteLink.Output { core.links.removeValue(forKey: input.path.id); return .noContent }

    // Discovery
    func listDiscoveredEndpoints(_ input: Operations.listDiscoveredEndpoints.Input) async throws -> Operations.listDiscoveredEndpoints.Output {
        // For now, mirror instruments as discovered endpoints
        let list: [Components.Schemas.DiscoveredEndpoint] = core.instruments.values.map { i in
            .init(id: i.id, identity: i.identity, propertySchema: i.propertySchema)
        }
        return .ok(.init(body: .json(list)))
    }
    func getDiscoveredEndpointSchema(_ input: Operations.getDiscoveredEndpointSchema.Input) async throws -> Operations.getDiscoveredEndpointSchema.Output {
        let id = input.path.id
        if let i = core.instruments[id] { return .ok(.init(body: .json(i.propertySchema))) }
        return .undocumented(statusCode: 404, .init())
    }

    // Suggest
    func suggestLinks(_ input: Operations.suggestLinks.Input) async throws -> Operations.suggestLinks.Output {
        // Simple heuristic: match identical property names across selected nodes, propose property links
        var ids: [String] = []
        if case let .json(body) = input.body { ids = body.nodeIds ?? [] }
        let nodes = (ids.isEmpty ? Array(core.instruments.keys) : ids)
        let props: [(String, Set<String>)] = nodes.compactMap { id in core.instruments[id].map { ($0.id, Set($0.propertySchema.properties.map { $0.name })) } }
        var suggestions: [Components.Schemas.SuggestedLink] = []
        for i in 0..<props.count {
            for j in (i+1)..<props.count {
                let common = props[i].1.intersection(props[j].1)
                for p in common {
                    let link = Components.Schemas.CreateLink(kind: .property, property: .init(from: "\(props[i].0).\(p)", to: "\(props[j].0).\(p)", direction: .a_to_b), ump: nil)
                    let s = Components.Schemas.SuggestedLink(link: link, reason: "matched property \(p)", confidence: 0.8)
                    suggestions.append(s)
                }
            }
        }
        return .ok(.init(body: .json(suggestions)))
    }

    // Import/Export
    func exportJSON(_ input: Operations.exportJSON.Input) async throws -> Operations.exportJSON.Output {
        let doc = Components.Schemas.GraphDoc(
            canvas: .init(width: core.canvas.docWidth, height: core.canvas.docHeight, theme: .init(rawValue: (core.canvas.theme?.rawValue) ?? "light") ?? .light, grid: core.canvas.gridStep),
            instruments: Array(core.instruments.values),
            links: Array(core.links.values),
            notes: []
        )
        return .ok(.init(body: .json(doc)))
    }
    func exportDSL(_ input: Operations.exportDSL.Input) async throws -> Operations.exportDSL.Output {
        let inst = Array(core.instruments.values)
        var lines: [String] = []
        let theme = core.canvas.theme?.rawValue ?? "light"
        lines.append("canvas \(core.canvas.docWidth)x\(core.canvas.docHeight) grid=\(core.canvas.gridStep) theme=\(theme)")
        for i in inst { lines.append("instrument \(i.id) kind=\(i.kind.rawValue) at (\(i.x),\(i.y)) size (\(i.w),\(i.h))") }
        for l in core.links.values { lines.append("link \(l.id) kind=\(l.kind.rawValue)") }
        let text = lines.joined(separator: "\n")
        return .ok(.init(body: .plainText(OpenAPIRuntime.HTTPBody(stringLiteral: text))))
    }
    func importJSON(_ input: Operations.importJSON.Input) async throws -> Operations.importJSON.Output {
        if case let .json(doc) = input.body {
            core.canvas.docWidth = doc.canvas.width
            core.canvas.docHeight = doc.canvas.height
            core.canvas.gridStep = doc.canvas.grid
            core.instruments = Dictionary(uniqueKeysWithValues: doc.instruments.map { ($0.id, $0) })
            core.links = Dictionary(uniqueKeysWithValues: doc.links.map { ($0.id, $0) })
        }
        return .noContent
    }
    func importDSL(_ input: Operations.importDSL.Input) async throws -> Operations.importDSL.Output { .noContent }

    // MARK: - Store (persistence)
    func listStoredGraphs(_ input: Operations.listStoredGraphs.Input) async throws -> Operations.listStoredGraphs.Output {
        do {
            let resp = try await store.query(corpusId: corpusId, collection: "patchbay.graphs", query: .init())
            let docs: [Components.Schemas.StoredGraph] = resp.documents.compactMap { data in
                try? JSONDecoder().decode(Components.Schemas.StoredGraph.self, from: data)
            }
            return .ok(.init(body: .json(docs)))
        } catch {
            return .ok(.init(body: .json([])))
        }
    }

    func getStoredGraph(_ input: Operations.getStoredGraph.Input) async throws -> Operations.getStoredGraph.Output {
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "patchbay.graphs", id: input.path.id) {
            if let g = try? JSONDecoder().decode(Components.Schemas.StoredGraph.self, from: data) {
                return .ok(.init(body: .json(g)))
            }
        }
        return .undocumented(statusCode: 404, .init())
    }

    func putStoredGraph(_ input: Operations.putStoredGraph.Input) async throws -> Operations.putStoredGraph.Output {
        guard case let .json(g) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var stored = g
        // Ensure timestamps and etag
        let now = Date()
        if stored.createdAt == nil { stored.createdAt = now }
        stored.updatedAt = now
        if stored.etag == nil { stored.etag = UUID().uuidString }
        let payload = try JSONEncoder().encode(stored)
        try? await store.putDoc(corpusId: corpusId, collection: "patchbay.graphs", id: stored.id, body: payload)
        return .noContent
    }

    // MARK: - Corpus (AI snapshot)
    func createCorpusSnapshot(_ input: Operations.createCorpusSnapshot.Input) async throws -> Operations.createCorpusSnapshot.Output {
        let ident = try? readVendorIdentity()
        let snap = Components.Schemas.CorpusSnapshot(version: 1, instruments: Array(core.instruments.values), links: Array(core.links.values), vendorIdentity: ident, notes: [])
        return .ok(.init(body: .json(snap)))
    }

    // MARK: - Admin (Vendor identity & sub-ID allocation)
    func getVendorIdentity(_ input: Operations.getVendorIdentity.Input) async throws -> Operations.getVendorIdentity.Output {
        if let v = try? readVendorIdentity() { return .ok(.init(body: .json(v))) }
        return .ok(.init(body: .json(.init())))
    }
    func putVendorIdentity(_ input: Operations.putVendorIdentity.Input) async throws -> Operations.putVendorIdentity.Output {
        guard case let .json(v) = input.body else { return .undocumented(statusCode: 400, .init()) }
        try writeVendorIdentity(v)
        return .noContent
    }
    func listVendorAllocations(_ input: Operations.listVendorAllocations.Input) async throws -> Operations.listVendorAllocations.Output {
        // List allocation documents from store
        do {
            let resp = try await store.query(corpusId: corpusId, collection: "patchbay.allocations", query: .init())
            let list: [Components.Schemas.Allocation] = resp.documents.compactMap { try? JSONDecoder().decode(Components.Schemas.Allocation.self, from: $0) }
            return .ok(.init(body: .json(list)))
        } catch {
            return .ok(.init(body: .json([])))
        }
    }
    func allocateSubId(_ input: Operations.allocateSubId.Input) async throws -> Operations.allocateSubId.Output {
        // Determine next subId by scanning existing allocations
        let existing: [Components.Schemas.Allocation]
        if let resp = try? await store.query(corpusId: corpusId, collection: "patchbay.allocations", query: .init()) {
            existing = resp.documents.compactMap { try? JSONDecoder().decode(Components.Schemas.Allocation.self, from: $0) }
        } else { existing = [] }
        let maxSub = existing.map { Int($0.subId) }.max() ?? -1
        let next = maxSub + 1
        // Read payload
        var instrumentId: String = ""
        if case let .json(payload) = input.body {
            // The generator creates a jsonPayload with instrumentId
            instrumentId = payload.instrumentId
        }
        let alloc = Components.Schemas.Allocation(instrumentId: instrumentId, subId: next, issuedAt: Date())
        if let data = try? JSONEncoder().encode(alloc) {
            try? await store.putDoc(corpusId: corpusId, collection: "patchbay.allocations", id: "alloc:\(instrumentId)", body: data)
        }
        return .created(.init(body: .json(alloc)))
    }

    // Secrets helpers
    private func readVendorIdentity() throws -> Components.Schemas.VendorIdentity? {
        if let d = try secrets.retrieveSecret(for: "VendorIdentity") {
            return try JSONDecoder().decode(Components.Schemas.VendorIdentity.self, from: d)
        }
        return nil
    }
    private func writeVendorIdentity(_ v: Components.Schemas.VendorIdentity) throws {
        let data = try JSONEncoder().encode(v)
        try secrets.storeSecret(data, for: "VendorIdentity")
    }
}
