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
    init(store: FountainStoreClient) {
        self.core = FountainEditorServerCore(store: store)
        self.placements = PlacementsStore(store: store)
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
    func get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Output { .ok(.init(body: .json([]))) }
    func post_sol_editor_sol__lcub_corpusId_rcub__sol_instruments(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_instruments.Output { .created(.init(body: .json(.init(instrumentId: UUID().uuidString, name: "stub", profile: .midi2sampler, programBase: nil, defaultMapping: nil, tags: nil, notes: nil)))) }
    func get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_(_ input: Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Input) async throws -> Operations.get_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Output { .undocumented(statusCode: 404, .init()) }
    func patch_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_(_ input: Operations.patch_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Input) async throws -> Operations.patch_sol_editor_sol__lcub_corpusId_rcub__sol_instruments_sol__lcub_instrumentId_rcub_.Output { .noContent(.init()) }

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

    func post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals.Output { .created(.init(body: .json(.init(proposalId: UUID().uuidString, createdAt: Date(), op: "", params: nil, anchor: nil, status: .pending)))) }
    func post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals_sol__lcub_proposalId_rcub_(_ input: Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals_sol__lcub_proposalId_rcub_.Input) async throws -> Operations.post_sol_editor_sol__lcub_corpusId_rcub__sol_proposals_sol__lcub_proposalId_rcub_.Output { .ok(.init(body: .json(.init(scriptETag: nil, applied: false, message: "not implemented")))) }
    func get_sol_editor_sol_sessions(_ input: Operations.get_sol_editor_sol_sessions.Input) async throws -> Operations.get_sol_editor_sol_sessions.Output { .ok(.init(body: .json([]))) }
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
