import Foundation
import OpenAPIRuntime
import FountainStoreClient
import fountain_editor_service_core

// Storage helpers
final class FountainEditorServerCore: @unchecked Sendable {
    let store: FountainStoreClient
    init(store: FountainStoreClient) { self.store = store }

    func pageId(for corpusId: String) -> String { "editor:script:\(corpusId)" }

    func ensurePage(corpusId: String) async {
        let pid = pageId(for: corpusId)
        let page = Page(corpusId: corpusId, pageId: pid, url: "store://\(pid)", host: "store", title: "Fountain Script \(corpusId)")
        _ = try? await store.addPage(page)
    }

    func getScript(corpusId: String) async -> (etag: String, text: String)? {
        let pid = pageId(for: corpusId)
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: "\(pid):text"),
           let seg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = seg["text"] as? String {
            let etag = FountainEditorCore.computeETag(for: text)
            return (etag, text)
        }
        return nil
    }

    func putScript(corpusId: String, body: String, ifMatch: String?) async -> (saved: Bool, newETag: String) {
        let current = await getScript(corpusId: corpusId)
        let currentETag = current?.etag ?? ""
        guard FountainEditorValidation.ifMatchSatisfied(currentETag: currentETag, header: ifMatch) else {
            return (false, currentETag)
        }
        await ensurePage(corpusId: corpusId)
        let pid = pageId(for: corpusId)
        // Save text segment
        let seg = Segment(corpusId: corpusId, segmentId: "\(pid):text", pageId: pid, kind: "text/plain", text: body)
        _ = try? await store.addSegment(seg)
        // Save structure facts
        let structure = FountainEditorCore.parseStructure(text: body)
        let dto = Components.Schemas.Structure(
            etag: structure.etag,
            acts: structure.acts.map { act in
                .init(index: act.index, title: act.title, scenes: act.scenes.map { sc in
                    .init(index: sc.index, title: sc.title, beats: sc.beats.map { .init(index: $0.index, title: $0.title) })
                })
            }
        )
        if let data = try? JSONEncoder().encode(dto), let json = String(data: data, encoding: .utf8) {
            let facts = Segment(corpusId: corpusId, segmentId: "\(pid):editor.structure", pageId: pid, kind: "editor.structure", text: json)
            _ = try? await store.addSegment(facts)
        }
        return (true, structure.etag)
    }
}

// Generated protocol conformance
final class FountainEditorHandlers: APIProtocol, @unchecked Sendable {
    let core: FountainEditorServerCore
    let placements: PlacementsStore
    let instruments: InstrumentsStore
    let proposals: ProposalsStore
    let sessions: SessionsStore
    init(store: FountainStoreClient) {
        self.core = FountainEditorServerCore(store: store)
        self.placements = PlacementsStore(store: store)
        self.instruments = InstrumentsStore(store: store)
        self.proposals = ProposalsStore(store: store)
        self.sessions = SessionsStore(store: store)
    }

    // GET /editor/health
    func get_sol_editor_sol_health(_ input: Operations.get_sol_editor_sol_health.Input) async throws -> Operations.get_sol_editor_sol_health.Output {
        let body = Components.Schemas.Health(ok: true, ready: true, version: "dev")
        return .ok(.init(body: .json(body)))
    }

    // GET /editor/{corpusId}/script
    func get_sol_editor_sol__lcub_corpusId_rcub__sol_script(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_script.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_script.Output {
        let cid = input.path.corpusId
        if let cur = await core.getScript(corpusId: cid) {
            let headers = Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_script.Output.Ok.Headers(ETag: cur.etag)
            return .ok(.init(headers: headers, body: .plainText(HTTPBody(cur.text))))
        }
        return .undocumented(statusCode: 404, .init())
    }

    // PUT /editor/{corpusId}/script
    func put_sol_editor_sol__lcub_corpusId_rcub__sol_script(_ input: Operations.put_sol_editor_sol__lcub_corpusId_rcub__sol_script.Input) async throws -> Operations.put_sol_editor_sol__lcub_corpusId_rcub__sol_script.Output {
        let cid = input.path.corpusId
        let text: String
        switch input.body {
        case .plainText(let b):
            text = try await String(collecting: b, upTo: 1<<20)
        }
        let ifm = input.headers.If_hyphen_Match
        // Require If-Match; return 400 when absent
        guard ifm != nil else { return .undocumented(statusCode: 400, .init()) }
        let result = await core.putScript(corpusId: cid, body: text, ifMatch: ifm)
        if result.saved {
            return .noContent(.init())
        } else {
            return .preconditionFailed(.init())
        }
    }

    // GET /editor/{corpusId}/structure
    func get_sol_editor_sol__lcub_corpusId_rcub__sol_structure(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_structure.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_structure.Output {
        let cid = input.path.corpusId
        guard let cur = await core.getScript(corpusId: cid) else { return .undocumented(statusCode: 404, .init()) }
        let s = FountainEditorCore.parseStructure(text: cur.text)
        let dto = Components.Schemas.Structure(
            etag: s.etag,
            acts: s.acts.map { act in
                Components.Schemas.Structure.actsPayloadPayload(
                    index: act.index,
                    title: act.title,
                    scenes: act.scenes.map { sc in
                        Components.Schemas.Structure.actsPayloadPayload.scenesPayloadPayload(
                            index: sc.index,
                            title: sc.title,
                            beats: sc.beats.map { b in
                                Components.Schemas.Structure.actsPayloadPayload.scenesPayloadPayload.beatsPayloadPayload(index: b.index, title: b.title)
                            }
                        )
                    }
                )
            }
        )
        return .ok(.init(body: .json(dto)))
    }

    // POST /editor/preview/parse
    func post_sol_editor_sol_preview_sol_parse(_ input: Operations.post_sol_editor_sol_preview_sol_parse.Input) async throws -> Operations.post_sol_editor_sol_preview_sol_parse.Output {
        let text: String
        switch input.body {
        case .plainText(let b):
            text = try await String(collecting: b, upTo: 1<<20)
        }
        let s = FountainEditorCore.parseStructure(text: text)
        let dto = Components.Schemas.Structure(
            etag: s.etag,
            acts: s.acts.map { act in
                Components.Schemas.Structure.actsPayloadPayload(
                    index: act.index,
                    title: act.title,
                    scenes: act.scenes.map { sc in
                        Components.Schemas.Structure.actsPayloadPayload.scenesPayloadPayload(
                            index: sc.index,
                            title: sc.title,
                            beats: sc.beats.map { b in
                                Components.Schemas.Structure.actsPayloadPayload.scenesPayloadPayload.beatsPayloadPayload(index: b.index, title: b.title)
                            }
                        )
                    }
                )
            }
        )
        return .ok(.init(body: .json(dto)))
    }

    // Stubs for endpoints not yet implemented
    func get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Output {
        let cid = input.path.corpusId
        let q = input.query.q
        let list = await instruments.list(corpusId: cid, query: q)
        return .ok(.init(body: .json(list)))
    }
    func post_sol_editor_sol__lcub_corpusId_rcub__sol_instruments(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Output {
        let cid = input.path.corpusId
        guard case .json(let create) = input.body else {
            return .undocumented(statusCode: 415, .init())
        }
        // Validate mapping if provided
        if let m = create.defaultMapping {
            try FountainEditorValidation.validateMapping(channels: m.channels?.map { Int($0) }, group: m.group.map { Int($0) }, filters: m.filters?.map { $0.rawValue })
        }
        let inst = await instruments.create(corpusId: cid, create: create)
        return .created(.init(body: .json(inst)))
    }
    func get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Output {
        let cid = input.path.corpusId
        let iid = input.path.instrumentId
        if let inst = await instruments.get(corpusId: cid, instrumentId: iid) {
            return .ok(.init(body: .json(inst)))
        }
        return .undocumented(statusCode: 404, .init())
    }
    func patch_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_(_ input: Operations.patch_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Input) async throws -> Operations.patch_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Output {
        let cid = input.path.corpusId
        let iid = input.path.instrumentId
        guard case .json(let upd) = input.body else { return .undocumented(statusCode: 415, .init()) }
        // Validate mapping if provided
        if let m = upd.defaultMapping {
            try FountainEditorValidation.validateMapping(channels: m.channels?.map { Int($0) }, group: m.group.map { Int($0) }, filters: m.filters?.map { $0.rawValue })
        }
        let ok = await instruments.update(corpusId: cid, instrumentId: iid, update: upd)
        return ok ? .noContent(.init()) : .undocumented(statusCode: 404, .init())
    }

    func get_sol_editor_sol__lcub_corpusId_rcub__sol_placements(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_placements.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_placements.Output {
        let cid = input.path.corpusId
        let anchor = input.query.anchor
        let list = await placements.list(corpusId: cid, anchor: anchor)
        let out: [Components.Schemas.Placement] = list.map { p in
            .init(placementId: p.id.uuidString, anchor: p.anchor, instrumentId: p.instrumentId, order: p.order, bus: p.bus, overrides: nil, notes: nil)
        }
        return .ok(.init(body: .json(out)))
    }
    func post_sol_editor_sol__lcub_corpusId_rcub__sol_placements(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_placements.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_placements.Output {
        let cid = input.path.corpusId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 400, .init()) }
        do {
            if let m = req.overrides {
                try FountainEditorValidation.validateMapping(channels: m.channels?.map { Int($0) }, group: m.group.map { Int($0) }, filters: m.filters?.map { $0.rawValue })
            }
        } catch {
            return .undocumented(statusCode: 400, .init())
        }
        let p = await placements.add(corpusId: cid, anchor: req.anchor, instrumentId: req.instrumentId, order: req.order.map { Int($0) }, bus: req.bus)
        let out = Components.Schemas.Placement(placementId: p.id.uuidString, anchor: p.anchor, instrumentId: p.instrumentId, order: p.order, bus: p.bus, overrides: nil, notes: req.notes)
        return .created(.init(body: .json(out)))
    }
    func patch_sol_editor_sol__lcub_corpusId_rcub__sol_placements_sol__lcub_placementId_rcub_(_ input: Operations.patch_sol_editor_sol__lcub_corpusId_rcub__sol_placements_sol__lcub_placementId_rcub_.Input) async throws -> Operations.patch_sol_editor_sol__lcub_corpusId_rcub__sol_placements_sol__lcub_placementId_rcub_.Output {
        let cid = input.path.corpusId
        let pid = input.path.placementId
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 400, .init()) }
        do {
            if let m = req.overrides {
                try FountainEditorValidation.validateMapping(channels: m.channels?.map { Int($0) }, group: m.group.map { Int($0) }, filters: m.filters?.map { $0.rawValue })
            }
        } catch {
            return .undocumented(statusCode: 400, .init())
        }
        let ok = await placements.update(corpusId: cid, id: pid, order: req.order.map { Int($0) }, bus: req.bus)
        return ok ? .noContent(.init()) : .undocumented(statusCode: 404, .init())
    }
    func delete_sol_editor_sol__lcub_corpusId_rcub__sol_placements_sol__lcub_placementId_rcub_(_ input: Operations.delete_sol_editor_sol__lcub_corpusId_rcub__sol_placements_sol__lcub_placementId_rcub_.Input) async throws -> Operations.delete_sol_editor_sol__lcub_corpusId_rcub__sol_placements_sol__lcub_placementId_rcub_.Output {
        let cid = input.path.corpusId
        let pid = input.path.placementId
        let ok = await placements.remove(corpusId: cid, id: pid)
        return ok ? .noContent(.init()) : .undocumented(statusCode: 404, .init())
    }

    func post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals.Output {
        let cid = input.path.corpusId
        guard case .json(let body) = input.body else { return .undocumented(statusCode: 415, .init()) }
        let p = await proposals.create(corpusId: cid, body: body)
        return .created(.init(body: .json(p)))
    }
    func post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals_sol__lcub_proposalId_rcub_(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals_sol__lcub_proposalId_rcub_.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals_sol__lcub_proposalId_rcub_.Output {
        let cid = input.path.corpusId
        let pid = input.path.proposalId
        guard case .json(let decision) = input.body else { return .undocumented(statusCode: 415, .init()) }
        if decision.decision == .accept {
            // Try to apply supported ops
            if let model = await proposals.getModel(corpusId: cid, proposalId: pid) {
                let applied = await applyProposal(corpusId: cid, model: model)
                if applied.applied {
                    _ = await proposals.setStatus(corpusId: cid, proposalId: pid, status: .accepted)
                    return .ok(.init(body: .json(Components.Schemas.ProposalResult(scriptETag: applied.newETag, applied: true, message: applied.message))))
                } else {
                    _ = await proposals.setStatus(corpusId: cid, proposalId: pid, status: .rejected)
                    return .ok(.init(body: .json(Components.Schemas.ProposalResult(scriptETag: nil, applied: false, message: applied.message))))
                }
            } else {
                return .ok(.init(body: .json(Components.Schemas.ProposalResult(scriptETag: nil, applied: false, message: "proposal not found"))))
            }
        } else {
            // Reject
            let _ = await proposals.setStatus(corpusId: cid, proposalId: pid, status: .rejected)
            return .ok(.init(body: .json(Components.Schemas.ProposalResult(scriptETag: nil, applied: false, message: "rejected"))))
        }
    }
    func get_sol_editor_sol_sessions(_ input: Operations.get_sol_editor_sol_sessions.Input) async throws -> Operations.get_sol_editor_sol_sessions.Output {
        let list = await sessions.list()
        return .ok(.init(body: .json(list)))
    }
}

// MARK: - Placements persistence in FountainStore
actor PlacementsStore {
    let store: FountainStoreClient
    init(store: FountainStoreClient) { self.store = store }

    private func pageId(_ corpusId: String) -> String { "editor:placements:\(corpusId)" }
    private func ensurePage(_ corpusId: String) async {
        let pid = pageId(corpusId)
        let page = Page(corpusId: corpusId, pageId: pid, url: "store://\(pid)", host: "store", title: "Fountain Placements \(corpusId)")
        _ = try? await store.addPage(page)
    }
    private func indexSegmentId(_ corpusId: String) -> String { "\(pageId(corpusId)):editor.placements.index" }
    private func anchorSegmentId(_ corpusId: String, _ anchor: String) -> String { "\(pageId(corpusId)):editor.placements.\(anchor)" }

    private func loadIndex(_ corpusId: String) async -> [String: String] {
        let segId = indexSegmentId(corpusId)
        guard let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String,
              let idx = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String] else { return [:] }
        return idx
    }
    private func saveIndex(_ corpusId: String, _ idx: [String: String]) async {
        await ensurePage(corpusId)
        let pid = pageId(corpusId)
        let json = (try? JSONSerialization.data(withJSONObject: idx, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let seg = Segment(corpusId: corpusId, segmentId: indexSegmentId(corpusId), pageId: pid, kind: "editor.placements.index", text: json)
        _ = try? await store.addSegment(seg)
    }
    private func loadAnchorList(_ corpusId: String, anchor: String) async -> [PlacementsCore.Placement] {
        let segId = anchorSegmentId(corpusId, anchor)
        guard let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String,
              let arr = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { return [] }
        return arr.compactMap { rec in
            guard let idStr = rec["placementId"] as? String, let id = UUID(uuidString: idStr),
                  let anchor = rec["anchor"] as? String,
                  let instrumentId = rec["instrumentId"] as? String else { return nil }
            let order = rec["order"] as? Int
            let bus = rec["bus"] as? String
            return PlacementsCore.Placement(id: id, anchor: anchor, instrumentId: instrumentId, order: order, bus: bus)
        }
    }
    private func saveAnchorList(_ corpusId: String, anchor: String, list: [PlacementsCore.Placement]) async {
        await ensurePage(corpusId)
        let pid = pageId(corpusId)
        let arr: [[String: Any]] = list.map { p in
            [
                "placementId": p.id.uuidString,
                "anchor": p.anchor,
                "instrumentId": p.instrumentId,
                "order": p.order as Any,
                "bus": p.bus as Any
            ].compactMapValues { $0 }
        }
        let json = (try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let seg = Segment(corpusId: corpusId, segmentId: anchorSegmentId(corpusId, anchor), pageId: pid, kind: "editor.placements", text: json)
        _ = try? await store.addSegment(seg)
    }

    func list(corpusId: String, anchor: String) async -> [PlacementsCore.Placement] {
        await loadAnchorList(corpusId, anchor: anchor)
    }
    @discardableResult
    func add(corpusId: String, anchor: String, instrumentId: String, order: Int?, bus: String?) async -> PlacementsCore.Placement {
        var list = await loadAnchorList(corpusId, anchor: anchor)
        let p = PlacementsCore.Placement(id: UUID(), anchor: anchor, instrumentId: instrumentId, order: order, bus: bus)
        list.append(p)
        await saveAnchorList(corpusId, anchor: anchor, list: list)
        var idx = await loadIndex(corpusId)
        idx[p.id.uuidString] = anchor
        await saveIndex(corpusId, idx)
        return p
    }
    func update(corpusId: String, id: String, order: Int?, bus: String?) async -> Bool {
        let idx = await loadIndex(corpusId)
        guard let anchor = idx[id], let uuid = UUID(uuidString: id) else { return false }
        var list = await loadAnchorList(corpusId, anchor: anchor)
        guard let pos = list.firstIndex(where: { $0.id == uuid }) else { return false }
        var p = list[pos]
        p.order = order ?? p.order
        p.bus = bus ?? p.bus
        list[pos] = p
        await saveAnchorList(corpusId, anchor: anchor, list: list)
        return true
    }
    func remove(corpusId: String, id: String) async -> Bool {
        var idx = await loadIndex(corpusId)
        guard let anchor = idx[id], let uuid = UUID(uuidString: id) else { return false }
        var list = await loadAnchorList(corpusId, anchor: anchor)
        let before = list.count
        list.removeAll { $0.id == uuid }
        await saveAnchorList(corpusId, anchor: anchor, list: list)
        idx.removeValue(forKey: id)
        await saveIndex(corpusId, idx)
        return list.count != before
    }
}

// MARK: - Instruments persistence
actor InstrumentsStore {
    private let store: FountainStoreClient
    init(store: FountainStoreClient) { self.store = store }
    private func pageId(_ corpusId: String) -> String { "editor:instruments:\(corpusId)" }
    private func listSegmentId(_ corpusId: String) -> String { "\(pageId(corpusId)):editor.instruments" }

    private func ensurePage(_ corpusId: String) async {
        let pid = pageId(corpusId)
        let page = Page(corpusId: corpusId, pageId: pid, url: "store://\(pid)", host: "store", title: "Instruments \(corpusId)")
        _ = try? await store.addPage(page)
    }

    struct Model: Codable, Sendable {
        var instrumentId: String
        var name: String
        var profile: Components.Schemas.Instrument.profilePayload
        var programBase: Int?
        var defaultMapping: Components.Schemas.Mapping?
        var tags: [String]?
        var notes: String?
    }

    private func loadList(_ corpusId: String) async -> [Model] {
        let segId = listSegmentId(corpusId)
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId),
           let seg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = seg["text"] as? String,
           let json = text.data(using: .utf8),
           let arr = try? JSONDecoder().decode([Model].self, from: json) {
            return arr
        }
        // Ensure page exists at first access
        await ensurePage(corpusId)
        return []
    }

    private func saveList(_ corpusId: String, _ list: [Model]) async {
        await ensurePage(corpusId)
        let pid = pageId(corpusId)
        let seg = Segment(corpusId: corpusId, segmentId: listSegmentId(corpusId), pageId: pid, kind: "editor.instruments", text: (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]")
        _ = try? await store.addSegment(seg)
    }

    func list(corpusId: String, query: String?) async -> [Components.Schemas.Instrument] {
        let q = query?.lowercased()
        let items = await loadList(corpusId)
        let filtered = q.map { needle in items.filter { $0.name.lowercased().contains(needle) || ($0.tags ?? []).contains { $0.lowercased().contains(needle) } } } ?? items
        return filtered.map { Components.Schemas.Instrument(instrumentId: $0.instrumentId, name: $0.name, profile: $0.profile, programBase: $0.programBase, defaultMapping: $0.defaultMapping, tags: $0.tags, notes: $0.notes) }
    }

    func create(corpusId: String, create: Components.Schemas.InstrumentCreate) async -> Components.Schemas.Instrument {
        var list = await loadList(corpusId)
        let id = UUID().uuidString
        let model = Model(instrumentId: id, name: create.name, profile: .midi2sampler, programBase: create.programBase.map { Int($0) }, defaultMapping: create.defaultMapping, tags: create.tags, notes: create.notes)
        list.append(model)
        await saveList(corpusId, list)
        return Components.Schemas.Instrument(instrumentId: id, name: model.name, profile: model.profile, programBase: model.programBase, defaultMapping: model.defaultMapping, tags: model.tags, notes: model.notes)
    }

    func get(corpusId: String, instrumentId: String) async -> Components.Schemas.Instrument? {
        let list = await loadList(corpusId)
        if let m = list.first(where: { $0.instrumentId == instrumentId }) {
            return Components.Schemas.Instrument(instrumentId: m.instrumentId, name: m.name, profile: m.profile, programBase: m.programBase, defaultMapping: m.defaultMapping, tags: m.tags, notes: m.notes)
        }
        return nil
    }

    func update(corpusId: String, instrumentId: String, update: Components.Schemas.InstrumentUpdate) async -> Bool {
        var list = await loadList(corpusId)
        guard let idx = list.firstIndex(where: { $0.instrumentId == instrumentId }) else { return false }
        var m = list[idx]
        if let name = update.name { m.name = name }
        if let pb = update.programBase { m.programBase = Int(pb) }
        if let map = update.defaultMapping { m.defaultMapping = map }
        if let tags = update.tags { m.tags = tags }
        if let notes = update.notes { m.notes = notes }
        list[idx] = m
        await saveList(corpusId, list)
        return true
    }
}

// MARK: - Proposal application helpers
extension FountainEditorHandlers {
    private func decodeParamsJSON(_ s: String?) -> [String: Any] {
        guard let s, let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// Applies a proposal if supported. Returns (applied, newETag, message).
    fileprivate func applyProposal(corpusId: String, model: ProposalsStore.Model) async -> (applied: Bool, newETag: String?, message: String) {
        let params = decodeParamsJSON(model.paramsJSON)
        let op = model.op
        // Load current script
        let cur = await core.getScript(corpusId: corpusId)
        let currentETag = cur?.etag
        var text = cur?.text ?? ""
        switch op {
        case "composeBlock":
            guard let block = params["text"] as? String, !block.isEmpty else { return (false, nil, "missing text") }
            if !text.isEmpty { text += "\n\n" }
            text += block
        case "insertScene":
            // Anchor-aware insertion: if an anchor is provided and we can locate
            // the corresponding scene heading, insert the new scene block right after it.
            // Fallback: append at end.
            let title = (params["title"] as? String) ?? "NEW SCENE"
            let slug = (params["slug"] as? String) ?? "INT. \(title.uppercased()) — DAY"
            let block = "\n\n## \(title)\n\n\(slug)\n"
            if let anchor = model.anchor, !anchor.isEmpty {
                // Try to find the scene title from current structure by anchor
                let structure = FountainEditorCore.parseStructure(text: text)
                if let scene = structure.acts.flatMap({ $0.scenes }).first(where: { $0.anchor == anchor }) {
                    // Insert right after line matching the scene heading
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    var out: [String] = []
                    var inserted = false
                    for i in 0..<lines.count {
                        out.append(lines[i])
                        if !inserted && lines[i].trimmingCharacters(in: .whitespaces) == "## \(scene.title)" {
                            out.append(contentsOf: block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
                            inserted = true
                        }
                    }
                    if inserted {
                        text = out.joined(separator: "\n")
                        break
                    }
                    // If we failed to match heading, fall through to append
                }
            }
            // Append at end
            text += block
        case "renameScene":
            // Rename the scene heading for the given anchor (or params.anchor) to params.title
            let newTitle = (params["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title = newTitle, !title.isEmpty else { return (false, nil, "missing title") }
            let targetAnchor = model.anchor ?? (params["anchor"] as? String)
            guard let anchor = targetAnchor, !anchor.isEmpty else { return (false, nil, "missing anchor") }
            let structure = FountainEditorCore.parseStructure(text: text)
            guard let scene = structure.acts.flatMap({ $0.scenes }).first(where: { $0.anchor == anchor }) else {
                return (false, nil, "anchor not found")
            }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var changed = false
            for i in 0..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "## \(scene.title)" {
                    // Preserve original leading whitespace if any
                    let prefixLen = lines[i].prefix { $0.isWhitespace }.count
                    let prefix = String(lines[i].prefix(prefixLen))
                    lines[i] = prefix + "## \(title)"
                    changed = true
                    break
                }
            }
            if !changed { return (false, nil, "heading not found") }
            text = lines.joined(separator: "\n")
        case "rewriteRange":
            // Replace a substring of the script by character offsets [start, end) with provided text
            guard let start = params["start"] as? Int, let end = params["end"] as? Int, start >= 0, end >= start, end <= text.count else {
                return (false, nil, "invalid range")
            }
            let replacement = (params["text"] as? String) ?? ""
            let sIdx = text.index(text.startIndex, offsetBy: start)
            let eIdx = text.index(text.startIndex, offsetBy: end)
            text.replaceSubrange(sIdx..<eIdx, with: replacement)
        case "moveScene":
            // Move a scene block (heading + body until next heading) relative to another scene.
            // Params: sourceAnchor (optional; defaults to model.anchor), targetAnchor (required), position: "after" (default) | "before".
            let sourceAnchor = model.anchor ?? (params["sourceAnchor"] as? String)
            guard let src = sourceAnchor, !src.isEmpty else { return (false, nil, "missing sourceAnchor") }
            guard let target = (params["targetAnchor"] as? String), !target.isEmpty else { return (false, nil, "missing targetAnchor") }
            let position = ((params["position"] as? String)?.lowercased() == "before") ? "before" : "after"
            if src == target { return (false, nil, "source==target") }

            let structure = FountainEditorCore.parseStructure(text: text)
            guard let srcScene = structure.acts.flatMap({ $0.scenes }).first(where: { $0.anchor == src }),
                  let dstScene = structure.acts.flatMap({ $0.scenes }).first(where: { $0.anchor == target }) else {
                return (false, nil, "anchor not found")
            }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // Map headings to indices
            var headingIdx: [String: Int] = [:] // title -> first line index of heading
            for i in 0..<lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("## ") {
                    let title = String(t.dropFirst(3))
                    headingIdx[title] = i
                }
            }
            guard let srcStart = headingIdx[srcScene.title], let dstStartInitial = headingIdx[dstScene.title] else {
                return (false, nil, "heading not found")
            }
            // Compute end indexes (exclusive) as next heading or EOF
            func blockEnd(start: Int) -> Int {
                var j = start + 1
                while j < lines.count {
                    if lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("## ") { break }
                    j += 1
                }
                return j
            }
            let srcEnd = blockEnd(start: srcStart)
            // Extract source block
            let block = Array(lines[srcStart..<srcEnd])
            // Remove it
            lines.removeSubrange(srcStart..<srcEnd)
            // Recompute destination start after removal
            var dstStart = dstStartInitial
            if srcStart < dstStart { dstStart -= (srcEnd - srcStart) }
            // Compute insertion index
            let insertIndex: Int = {
                if position == "before" { return dstStart }
                // after => after the destination block
                let dstEnd = blockEnd(start: dstStart)
                return dstEnd
            }()
            // Insert a separating blank line if needed
            var insertBlock = block
            if insertIndex > 0, insertIndex <= lines.count {
                // Ensure preceding line ends with a blank separation for readability
                if lines.indices.contains(insertIndex - 1) {
                    if !lines[max(0, insertIndex - 1)].isEmpty, (insertBlock.first?.isEmpty ?? false) == false {
                        insertBlock.insert("", at: 0)
                    }
                }
            }
            lines.insert(contentsOf: insertBlock, at: insertIndex)
            text = lines.joined(separator: "\n")
        case "splitScene":
            // Split a scene into two. Params: anchor (optional, defaults model.anchor), newTitle (default: "Split"), atLine (Int >=0) offset from the first content line after heading.
            let targetAnchor = model.anchor ?? (params["anchor"] as? String)
            guard let anchor = targetAnchor, !anchor.isEmpty else { return (false, nil, "missing anchor") }
            let newTitle = (params["newTitle"] as? String) ?? "Split"
            let atLine = (params["atLine"] as? Int) ?? 0
            let structure = FountainEditorCore.parseStructure(text: text)
            guard let scene = structure.acts.flatMap({ $0.scenes }).first(where: { $0.anchor == anchor }) else {
                return (false, nil, "anchor not found")
            }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // locate heading
            var headingIndex: Int? = nil
            for i in 0..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "## \(scene.title)" { headingIndex = i; break }
            }
            guard let startIdx = headingIndex else { return (false, nil, "heading not found") }
            // compute end of block
            var endIdx = startIdx + 1
            while endIdx < lines.count {
                if lines[endIdx].trimmingCharacters(in: .whitespaces).hasPrefix("## ") { break }
                endIdx += 1
            }
            let contentStart = startIdx + 1
            let contentLines = max(0, endIdx - contentStart)
            let splitOffset = max(0, min(atLine, contentLines))
            let splitIdx = contentStart + splitOffset
            // New scene block: blank line + heading + slug, then the tail content
            let slug = "INT. \(newTitle.uppercased()) — DAY"
            var newBlock: [String] = []
            if splitIdx < lines.count, !(lines[splitIdx].isEmpty) { newBlock.append("") }
            newBlock.append("## \(newTitle)")
            newBlock.append("")
            newBlock.append(slug)
            // Tail content from splitIdx ..< endIdx
            if splitIdx < endIdx {
                newBlock.append(contentsOf: lines[splitIdx..<endIdx])
            }
            // Truncate original scene content after splitIdx
            if splitIdx < endIdx { lines.removeSubrange(splitIdx..<endIdx) }
            // Insert new block right after the (possibly shortened) original block
            var insertAt = splitIdx
            // If we removed a range, indices shifted; insertAt now points to former splitIdx location (correct)
            lines.insert(contentsOf: newBlock, at: insertAt)
            text = lines.joined(separator: "\n")
        case "applyPatch":
            // Apply multiple range edits: params.edits = [{start:Int,end:Int,text:String}, ...]
            guard let editsAny = params["edits"] as? [Any], !editsAny.isEmpty else { return (false, nil, "missing edits") }
            struct Edit { let start: Int; let end: Int; let text: String }
            var edits: [Edit] = []
            for e in editsAny {
                guard let m = e as? [String: Any], let s = m["start"] as? Int, let en = m["end"] as? Int else { return (false, nil, "invalid edit") }
                let t = (m["text"] as? String) ?? ""
                if s < 0 || en < s || en > text.count { return (false, nil, "invalid range") }
                edits.append(Edit(start: s, end: en, text: t))
            }
            // Apply in descending order to avoid offset shifts
            edits.sort { $0.start > $1.start }
            for e in edits {
                let sIdx = text.index(text.startIndex, offsetBy: e.start)
                let eIdx = text.index(text.startIndex, offsetBy: e.end)
                text.replaceSubrange(sIdx..<eIdx, with: e.text)
            }
        default:
            return (false, nil, "unsupported op \(op)")
        }
        // Save via ETag gate
        let ifMatch = currentETag ?? "*"
        let res = await core.putScript(corpusId: corpusId, body: text, ifMatch: ifMatch)
        if res.saved { return (true, res.newETag, "applied \(op)") }
        return (false, nil, "precondition failed (ETag)")
    }
}

// MARK: - Proposals persistence
actor ProposalsStore {
    private let store: FountainStoreClient
    init(store: FountainStoreClient) { self.store = store }
    private func pageId(_ corpusId: String) -> String { "editor:proposals:\(corpusId)" }
    private func listSegmentId(_ corpusId: String) -> String { "\(pageId(corpusId)):editor.proposals" }

    struct Model: Codable {
        var proposalId: String
        var createdAt: Date
        var op: String
        var anchor: String?
        var status: Components.Schemas.Proposal.statusPayload
        var paramsJSON: String?
    }

    private func ensurePage(_ corpusId: String) async {
        let pid = pageId(corpusId)
        let page = Page(corpusId: corpusId, pageId: pid, url: "store://\(pid)", host: "store", title: "Proposals \(corpusId)")
        _ = try? await store.addPage(page)
    }

    private func loadList(_ corpusId: String) async -> [Model] {
        let segId = listSegmentId(corpusId)
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId),
           let seg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = seg["text"] as? String,
           let json = text.data(using: .utf8) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let arr = try? dec.decode([Model].self, from: json) { return arr }
        }
        await ensurePage(corpusId)
        return []
    }

    private func saveList(_ corpusId: String, _ list: [Model]) async {
        await ensurePage(corpusId)
        let pid = pageId(corpusId)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let text = (try? String(data: enc.encode(list), encoding: .utf8)) ?? "[]"
        let seg = Segment(corpusId: corpusId, segmentId: listSegmentId(corpusId), pageId: pid, kind: "editor.proposals", text: text)
        _ = try? await store.addSegment(seg)
    }

    func create(corpusId: String, body: Components.Schemas.ProposalCreate) async -> Components.Schemas.Proposal {
        var list = await loadList(corpusId)
        var paramsStr: String? = nil
        if let p = body.params, let data = try? JSONEncoder().encode(p) { paramsStr = String(data: data, encoding: .utf8) }
        let model = Model(proposalId: UUID().uuidString, createdAt: Date(), op: body.op.rawValue, anchor: body.anchor, status: .pending, paramsJSON: paramsStr)
        list.append(model)
        await saveList(corpusId, list)
        return Components.Schemas.Proposal(proposalId: model.proposalId, createdAt: model.createdAt, op: model.op, params: body.params?.additionalProperties, anchor: model.anchor, status: model.status)
    }

    func decide(corpusId: String, proposalId: String, decision: Components.Schemas.ProposalDecision) async -> Components.Schemas.ProposalResult {
        var list = await loadList(corpusId)
        if let idx = list.firstIndex(where: { $0.proposalId == proposalId }) {
            var m = list[idx]
            m.status = (decision.decision == .accept) ? .accepted : .rejected
            list[idx] = m
            await saveList(corpusId, list)
            // Not applying patches yet; return applied=false and no ETag change
            return Components.Schemas.ProposalResult(scriptETag: nil, applied: false, message: "decision recorded: \(decision.decision.rawValue)")
        }
        return Components.Schemas.ProposalResult(scriptETag: nil, applied: false, message: "proposal not found")
    }

    func getModel(corpusId: String, proposalId: String) async -> Model? {
        let list = await loadList(corpusId)
        return list.first(where: { $0.proposalId == proposalId })
    }

    func setStatus(corpusId: String, proposalId: String, status: Components.Schemas.Proposal.statusPayload) async -> Bool {
        var list = await loadList(corpusId)
        if let idx = list.firstIndex(where: { $0.proposalId == proposalId }) {
            var m = list[idx]
            m.status = status
            list[idx] = m
            await saveList(corpusId, list)
            return true
        }
        return false
    }
}


// MARK: - Sessions list (global)
actor SessionsStore {
    private let store: FountainStoreClient
    init(store: FountainStoreClient) { self.store = store }
    private func pageId() -> String { "editor:sessions" }
    private func segmentId() -> String { "\(pageId()):editor.sessions" }

    private func load() async -> [Components.Schemas.ChatSession] {
        let cid = "fountain-editor"
        let seg = segmentId()
        if let data = try? await store.getDoc(corpusId: cid, collection: "segments", id: seg),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String,
           let json = text.data(using: .utf8),
           let arr = try? JSONDecoder().decode([Components.Schemas.ChatSession].self, from: json) {
            return arr
        }
        return []
    }

    func list() async -> [Components.Schemas.ChatSession] { await load() }
}
