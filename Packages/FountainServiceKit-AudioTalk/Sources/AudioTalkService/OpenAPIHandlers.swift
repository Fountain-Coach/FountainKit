import Foundation
import OpenAPIRuntime
import FountainStoreClient
import MIDI2Transports

actor AudioTalkState {
    struct NotationEntry: Codable { var source: String; var eTag: String; var createdAt: Date }
    struct ScreenplayEntry: Codable { var source: String; var eTag: String; var createdAt: Date }

    // Optional persistence; when nil, falls back to in-memory maps.
    private let store: FountainStoreClient?
    private let corpusId: String

    private var dictionaryMem: [String: Components.Schemas.DictionaryItem] = [:]
    private var macrosMem: [String: Components.Schemas.Macro] = [:]
    private var notationMem: [String: NotationEntry] = [:]
    private var screenplayMem: [String: ScreenplayEntry] = [:]

    // Additional collections for derived data
    private var screenplayIndexColl: String { "audiotalk_screenplay_index" }
    private var cuesColl: String { "audiotalk_cues" }
    private var journalColl: String { "audiotalk_journal" }
    private var umpColl: String { "audiotalk_ump" }

    init(store: FountainStoreClient? = nil, corpusId: String = "audiotalk") {
        self.store = store
        self.corpusId = corpusId
    }

    private func newETag() -> String { UUID().uuidString }

    // MARK: Collections
    private var dictColl: String { "audiotalk_dictionary" }
    private var macroColl: String { "audiotalk_macros" }
    private var notationColl: String { "audiotalk_notation" }
    private var screenplayColl: String { "audiotalk_screenplay" }

    // MARK: Dictionary
    func listDictionary(limit: Int = 50, after: String? = nil) async -> Components.Schemas.DictionaryList {
        if let store {
            do {
                let resp = try await store.query(corpusId: corpusId, collection: dictColl, query: .init(limit: limit, offset: 0))
                let items = try resp.documents.map { try JSONDecoder().decode(Components.Schemas.DictionaryItem.self, from: $0) }
                return .init(items: items, nextPage: nil)
            } catch { /* fall back */ }
        }
        let sorted = dictionaryMem.keys.sorted()
        let startIndex = after.flatMap { sorted.firstIndex(of: $0) }.map { sorted.index(after: $0) } ?? sorted.startIndex
        let slice = sorted[startIndex...].prefix(limit)
        let items = slice.compactMap { dictionaryMem[$0] }
        let next = slice.count == limit ? slice.last : nil
        return .init(items: items, nextPage: next)
    }
    func upsertDictionary(_ req: Components.Schemas.DictionaryUpsertRequest) async -> Components.Schemas.DictionaryUpsertResponse {
        var updated = 0
        guard let items = req.items, !items.isEmpty else { return .init(updated: 0) }
        if let store {
            do {
                for it in items {
                    let data = try JSONEncoder().encode(it)
                    try await store.putDoc(corpusId: corpusId, collection: dictColl, id: it.token, body: data)
                    updated += 1
                }
                return .init(updated: updated)
            } catch { /* fall back */ updated = 0 }
        }
        for it in items { dictionaryMem[it.token] = it; updated += 1 }
        return .init(updated: updated)
    }

    // MARK: Macros
    func listMacros(limit: Int = 50, after: String? = nil) async -> Components.Schemas.MacroList {
        if let store {
            do {
                let resp = try await store.query(corpusId: corpusId, collection: macroColl, query: .init(limit: limit, offset: 0))
                let items = try resp.documents.map { try JSONDecoder().decode(Components.Schemas.Macro.self, from: $0) }
                return .init(items: items, nextPage: nil)
            } catch { /* fall back */ }
        }
        let sorted = macrosMem.keys.sorted()
        let startIndex = after.flatMap { sorted.firstIndex(of: $0) }.map { sorted.index(after: $0) } ?? sorted.startIndex
        let slice = sorted[startIndex...].prefix(limit)
        let items = slice.compactMap { macrosMem[$0] }
        let next = slice.count == limit ? slice.last : nil
        return .init(items: items, nextPage: next)
    }
    func createMacro(id: String, plan: Components.Schemas.Plan) async -> Components.Schemas.Macro {
        var m = Components.Schemas.Macro(id: id, state: .proposed, plan: plan, created_at: Date())
        if let store {
            do {
                let data = try JSONEncoder().encode(m)
                try await store.putDoc(corpusId: corpusId, collection: macroColl, id: id, body: data)
                return m
            } catch { /* fall back */ }
        }
        macrosMem[id] = m
        return m
    }
    func promoteMacro(id: String) async -> Components.Schemas.Macro? {
        if let store {
            do {
                if let data = try await store.getDoc(corpusId: corpusId, collection: macroColl, id: id) {
                    var m = try JSONDecoder().decode(Components.Schemas.Macro.self, from: data)
                    m.state = .approved
                    let out = try JSONEncoder().encode(m)
                    try await store.putDoc(corpusId: corpusId, collection: macroColl, id: id, body: out)
                    return m
                }
            } catch { return nil }
        }
        guard var m = macrosMem[id] else { return nil }
        m.state = .approved
        macrosMem[id] = m
        return m
    }

    // MARK: Notation
    func createNotationSession() async -> Components.Schemas.NotationSession {
        let id = UUID().uuidString
        let entry = NotationEntry(source: "", eTag: newETag(), createdAt: Date())
        if let store {
            do {
                let data = try JSONEncoder().encode(entry)
                try await store.putDoc(corpusId: corpusId, collection: notationColl, id: id, body: data)
                return .init(id: id, created_at: entry.createdAt)
            } catch { /* fall back */ }
        }
        notationMem[id] = entry
        return .init(id: id, created_at: entry.createdAt)
    }
    func getNotationSession(id: String) async -> Components.Schemas.NotationSession? {
        if let store {
            do {
                if let data = try await store.getDoc(corpusId: corpusId, collection: notationColl, id: id) {
                    let e = try JSONDecoder().decode(NotationEntry.self, from: data)
                    return .init(id: id, created_at: e.createdAt)
                }
                return nil
            } catch { return nil }
        }
        guard let e = notationMem[id] else { return nil }
        return .init(id: id, created_at: e.createdAt)
    }
    func getLilySource(id: String) async -> (etag: String, body: String)? {
        if let store {
            do {
                if let data = try await store.getDoc(corpusId: corpusId, collection: notationColl, id: id) {
                    let e = try JSONDecoder().decode(NotationEntry.self, from: data)
                    return (e.eTag, e.source)
                }
                return nil
            } catch { return nil }
        }
        guard let e = notationMem[id] else { return nil }
        return (e.eTag, e.source)
    }
    func putLilySource(id: String, ifMatch: String?, body: String) async -> (ok: Bool, newETag: String)? {
        if let store {
            do {
                guard let data = try await store.getDoc(corpusId: corpusId, collection: notationColl, id: id) else { return nil }
                var e = try JSONDecoder().decode(NotationEntry.self, from: data)
                if let ifm = ifMatch, ifm != e.eTag { return (false, e.eTag) }
                e.source = body
                e.eTag = newETag()
                try await store.putDoc(corpusId: corpusId, collection: notationColl, id: id, body: try JSONEncoder().encode(e))
                return (true, e.eTag)
            } catch { return nil }
        }
        guard var e = notationMem[id] else { return nil }
        if let ifm = ifMatch, ifm != e.eTag { return (false, e.eTag) }
        e.source = body; e.eTag = newETag(); notationMem[id] = e
        return (true, e.eTag)
    }

    // Apply plan to notation session by appending annotated LilyPond comments.
    struct ApplyResult { let ok: Bool; let newETag: String; let appliedOps: [Components.Schemas.PlanOp]; let etagMismatch: Bool }
    private func mapTokenToLily(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // Heuristic: treat simple lily tokens as-is
        if let first = t.first, "abcdefgABCDEFG".contains(first) {
            return t
        }
        // Tempo: tempo:120 -> \tempo 4 = 120
        if t.lowercased().hasPrefix("tempo:") {
            let num = t.split(separator: ":").last.map(String.init) ?? "120"
            return "\\tempo 4 = \(num)"
        }
        // Dynamics: p, mp, mf, f
        let dyns: Set<String> = ["pp","p","mp","mf","f","ff"]
        if dyns.contains(t.lowercased()) { return "\\\(t.lowercased())" }
        // Default: text markup
        let escaped = t.replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "\\", with: "\\\\")
        return "\\markup { \"\(escaped)\" }"
    }

    private func lilyForPlan(_ plan: Components.Schemas.Plan, label: String? = nil, anchor: Components.Schemas.ScriptAnchor? = nil) -> String {
        var parts: [String] = []
        if let label { parts.append("Cue: \(label)") }
        if let s = anchor?.scene_number { parts.append("scene \(s)") }
        if let l = anchor?.line { parts.append("line \(l)") }
        let header = parts.isEmpty ? "% AudioTalk Cue" : "% AudioTalk \(parts.joined(separator: ", "))"
        let tokens = plan.ops.map { op in mapTokenToLily(op.value ?? op.kind.rawValue) }
        let body = tokens.joined(separator: " ")
        return [header, "{ \(body) }"].joined(separator: "\n")
    }

    func applyPlanToNotation(sessionId: String, ifMatch: String?, plan: Components.Schemas.Plan) async -> ApplyResult? {
        // Build Lily block from the plan tokens.
        let block = lilyForPlan(plan)
        // Disk-backed store
        if let store {
            do {
                guard let data = try await store.getDoc(corpusId: corpusId, collection: notationColl, id: sessionId) else { return nil }
                var e = try JSONDecoder().decode(NotationEntry.self, from: data)
                if let ifm = ifMatch, ifm != e.eTag { return .init(ok: false, newETag: e.eTag, appliedOps: [], etagMismatch: true) }
                let sep = e.source.isEmpty ? "" : "\n"
                e.source += sep + block + "\n"
                e.eTag = newETag()
                try await store.putDoc(corpusId: corpusId, collection: notationColl, id: sessionId, body: try JSONEncoder().encode(e))
                return .init(ok: true, newETag: e.eTag, appliedOps: plan.ops, etagMismatch: false)
            } catch { return nil }
        }
        // In-memory fallback
        guard var e = notationMem[sessionId] else { return nil }
        if let ifm = ifMatch, ifm != e.eTag { return .init(ok: false, newETag: e.eTag, appliedOps: [], etagMismatch: true) }
        let sep = e.source.isEmpty ? "" : "\n"
        e.source += sep + block + "\n"
        e.eTag = newETag(); notationMem[sessionId] = e
        return .init(ok: true, newETag: e.eTag, appliedOps: plan.ops, etagMismatch: false)
    }

    // MARK: Screenplay
    func createScreenplaySession() async -> Components.Schemas.ScreenplaySession {
        let id = UUID().uuidString
        let entry = ScreenplayEntry(source: "", eTag: newETag(), createdAt: Date())
        let caps = Components.Schemas.Capabilities(rendering: false, ump_streaming: true, reflection: false)
        if let store {
            do {
                try await store.putDoc(corpusId: corpusId, collection: screenplayColl, id: id, body: try JSONEncoder().encode(entry))
                return .init(id: id, created_at: entry.createdAt, capabilities: caps)
            } catch { /* fall back */ }
        }
        screenplayMem[id] = entry
        return .init(id: id, created_at: entry.createdAt, capabilities: caps)
    }
    func getScreenplaySource(id: String) async -> (etag: String, body: String)? {
        if let store {
            do {
                if let data = try await store.getDoc(corpusId: corpusId, collection: screenplayColl, id: id) {
                    let e = try JSONDecoder().decode(ScreenplayEntry.self, from: data)
                    return (e.eTag, e.source)
                }
                return nil
            } catch { return nil }
        }
        guard let e = screenplayMem[id] else { return nil }
        return (e.eTag, e.source)
    }
    func putScreenplaySource(id: String, ifMatch: String?, body: String) async -> (ok: Bool, newETag: String)? {
        if let store {
            do {
                guard let data = try await store.getDoc(corpusId: corpusId, collection: screenplayColl, id: id) else { return nil }
                var e = try JSONDecoder().decode(ScreenplayEntry.self, from: data)
                if let ifm = ifMatch, ifm != e.eTag { return (false, e.eTag) }
                e.source = body
                e.eTag = newETag()
                try await store.putDoc(corpusId: corpusId, collection: screenplayColl, id: id, body: try JSONEncoder().encode(e))
                return (true, e.eTag)
            } catch { return nil }
        }
        guard var e = screenplayMem[id] else { return nil }
        if let ifm = ifMatch, ifm != e.eTag { return (false, e.eTag) }
        e.source = body; e.eTag = newETag(); screenplayMem[id] = e
        return (true, e.eTag)
    }

    // MARK: Parsed Model Persistence
    struct PersistedScreenplayModel: Codable {
        var id: String
        var etag: String
        var model: Components.Schemas.ScreenplayModel
        var updatedAt: Date
    }
    func persistParsedScreenplayModel(id: String, etag: String, model: Components.Schemas.ScreenplayModel) async {
        guard let store else { return }
        do {
            let payload = PersistedScreenplayModel(id: id, etag: etag, model: model, updatedAt: Date())
            try await store.putDoc(corpusId: corpusId, collection: screenplayIndexColl, id: id, body: try JSONEncoder().encode(payload))
        } catch { }
    }
    func loadParsedScreenplayModel(id: String) async -> PersistedScreenplayModel? {
        guard let store else { return nil }
        do {
            if let data = try await store.getDoc(corpusId: corpusId, collection: screenplayIndexColl, id: id) {
                return try JSONDecoder().decode(PersistedScreenplayModel.self, from: data)
            }
            return nil
        } catch { return nil }
    }

    // MARK: Cue Plans Persistence
    struct PersistedCues: Codable { var id: String; var cues: [Components.Schemas.CuePlan] }
    func persistCues(id: String, cues: [Components.Schemas.CuePlan]) async {
        guard let store else { return }
        do {
            let payload = PersistedCues(id: id, cues: cues)
            try await store.putDoc(corpusId: corpusId, collection: cuesColl, id: id, body: try JSONEncoder().encode(payload))
        } catch { }
    }
    func loadCues(id: String) async -> [Components.Schemas.CuePlan]? {
        guard let store else { return nil }
        do {
            if let data = try await store.getDoc(corpusId: corpusId, collection: cuesColl, id: id) {
                let payload = try JSONDecoder().decode(PersistedCues.self, from: data)
                return payload.cues
            }
            return nil
        } catch { return nil }
    }

    // MARK: Journal Persistence
    struct PersistedJournalEvent: Codable {
        var id: String
        var type: String
        var ts: Date
        var correlationId: String?
        var details: [String:String]
    }
    func appendJournal(type: String, correlationId: String? = nil, details: [String:String] = [:]) async {
        guard let store else { return }
        let ev = PersistedJournalEvent(id: UUID().uuidString, type: type, ts: Date(), correlationId: correlationId, details: details)
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            try await store.putDoc(corpusId: corpusId, collection: journalColl, id: ev.id, body: try enc.encode(ev))
        } catch { }
    }
    func listJournal(limit: Int = 50, offset: Int = 0) async -> [Components.Schemas.JournalEvent] {
        guard let store else { return [] }
        do {
            let resp = try await store.query(corpusId: corpusId, collection: journalColl, query: .init(limit: limit, offset: offset))
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            let decoded: [PersistedJournalEvent] = try resp.documents.map { try dec.decode(PersistedJournalEvent.self, from: $0) }
            return decoded.map { d in
                Components.Schemas.JournalEvent(
                    id: d.id,
                    _type: .init(rawValue: d.type) ?? .received,
                    ts: d.ts,
                    correlationId: d.correlationId,
                    details: .init(additionalProperties: d.details)
                )
            }
        } catch {
            return []
        }
    }

    // MARK: UMP Persistence
    struct PersistedUMPEvent: Codable {
        var id: String
        var session: String
        var jr_timestamp: Int?
        var host_time_ns: Int?
        var ump: String
        var receivedAt: Date
    }
    private var umpMem: [String: [PersistedUMPEvent]] = [:]
    func persistUMPEvent(session: String, jr: Int?, host: Int?, ump: String) async {
        let ev = PersistedUMPEvent(id: UUID().uuidString, session: session, jr_timestamp: jr, host_time_ns: host, ump: ump, receivedAt: Date())
        if let store {
            do {
                try await store.putDoc(corpusId: corpusId, collection: umpColl, id: ev.id, body: try JSONEncoder().encode(ev))
                return
            } catch { /* fall back */ }
        }
        var arr = umpMem[session] ?? []
        arr.append(ev)
        umpMem[session] = arr
    }
    func listUMPEvents(session: String, limit: Int = 50, offset: Int = 0) async -> [PersistedUMPEvent] {
        if let store {
            do {
                let resp = try await store.query(corpusId: corpusId, collection: umpColl, query: .init(filters: ["session": session], limit: limit, offset: offset))
                return try resp.documents.map { try JSONDecoder().decode(PersistedUMPEvent.self, from: $0) }
            } catch { /* fall back */ }
        }
        let arr = umpMem[session] ?? []
        if offset >= arr.count { return [] }
        let end = min(offset + limit, arr.count)
        return Array(arr[offset..<end])
    }
}

// Minimal server stubs for the AudioTalk OpenAPI.
// These compile against the Apple Swift OpenAPI Generator protocol and return
// placeholder responses. We will incrementally replace them with real logic.

public struct AudioTalkOpenAPI: APIProtocol, @unchecked Sendable {
    let state: AudioTalkState

    // Internal designated initializer for dependency injection in tests.
    init(state: AudioTalkState) { self.state = state }

    // Public convenience initializer for external modules (servers).
    public init() { self.state = AudioTalkState() }

    // Public initializer with persistence backing.
    public init(store: FountainStoreClient, corpusId: String = "audiotalk") {
        self.state = AudioTalkState(store: store, corpusId: corpusId)
    }

    // Helper to build generic JSON objects without generated schema types.
    private func jsonObject(_ dict: [String: (any Sendable)?]) -> OpenAPIObjectContainer? {
        try? OpenAPIObjectContainer(unvalidatedValue: dict)
    }

    // MARK: - Meta
    public func getAudioTalkHealth(_ input: Operations.getAudioTalkHealth.Input) async throws -> Operations.getAudioTalkHealth.Output {
        let payload = Operations.getAudioTalkHealth.Output.Ok.Body.jsonPayload(ok: true)
        return .ok(.init(body: .json(payload)))
    }

    public func getAudioTalkCapabilities(_ input: Operations.getAudioTalkCapabilities.Input) async throws -> Operations.getAudioTalkCapabilities.Output {
        let caps = Components.Schemas.Capabilities(rendering: false, ump_streaming: true, reflection: false)
        return .ok(.init(body: .json(caps)))
    }

    // MARK: - Sessions
    public func createAudioTalkSession(_ input: Operations.createAudioTalkSession.Input) async throws -> Operations.createAudioTalkSession.Output {
        let caps = Components.Schemas.Capabilities(rendering: false, ump_streaming: true, reflection: false)
        let out = Components.Schemas.SessionCreateResponse(session_id: UUID().uuidString, capabilities: caps)
        let headers = Operations.createAudioTalkSession.Output.Created.Headers(ETag: UUID().uuidString)
        return .created(.init(headers: headers, body: .json(out)))
    }

    // MARK: - Dictionary
    public func listDictionary(_ input: Operations.listDictionary.Input) async throws -> Operations.listDictionary.Output {
        let out = await state.listDictionary(limit: 50, after: nil)
        return .ok(.init(body: .json(out)))
    }

    public func upsertDictionary(_ input: Operations.upsertDictionary.Input) async throws -> Operations.upsertDictionary.Output {
        guard case let .json(req) = input.body else { return .badRequest(.init(body: .json(.init(error: "Bad Request", code: "bad_request", correlationId: nil)))) }
        let out = await state.upsertDictionary(req)
        return .ok(.init(body: .json(out)))
    }

    // MARK: - Macros
    public func listMacros(_ input: Operations.listMacros.Input) async throws -> Operations.listMacros.Output {
        let out = await state.listMacros(limit: 50, after: nil)
        return .ok(.init(body: .json(out)))
    }

    public func createMacro(_ input: Operations.createMacro.Input) async throws -> Operations.createMacro.Output {
        guard case let .json(req) = input.body else { return .badRequest(.init(body: .json(.init(error: "Bad Request", code: "bad_request", correlationId: nil)))) }
        let m = await state.createMacro(id: req.id, plan: req.plan)
        return .created(.init(body: .json(m)))
    }

    public func promoteMacro(_ input: Operations.promoteMacro.Input) async throws -> Operations.promoteMacro.Output {
        if let m = await state.promoteMacro(id: input.path.macroId) {
            return .ok(.init(body: .json(m)))
        }
        return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
    }

    // MARK: - Intent
    public func parseIntent(_ input: Operations.parseIntent.Input) async throws -> Operations.parseIntent.Output {
        guard case let .json(req) = input.body else { return .badRequest(.init(body: .json(.init(error: "Bad Request", code: "bad_request", correlationId: nil)))) }
        let tokens = req.phrase.split(separator: " ").map(String.init)
        let ops = tokens.map { t in Components.Schemas.PlanOp(id: UUID().uuidString, kind: .token, value: t, anchor: nil) }
        let plan = Components.Schemas.Plan(ops: ops, meta: .init(origin: .user, confidence: 1.0, source: nil))
        let out = Components.Schemas.IntentResponse(plan: plan, tokens: tokens, warnings: [])
        return .ok(.init(body: .json(out)))
    }

    public func parseIntentStream(_ input: Operations.parseIntentStream.Input) async throws -> Operations.parseIntentStream.Output {
        // Compose a simple SSE stream with token events and a final plan payload.
        guard case let .json(req) = input.body else {
            let sse = "event: error\ndata: {\"error\":\"bad_request\"}\n\n"
            return .accepted(.init(body: .text_event_hyphen_stream(HTTPBody(sse))))
        }
        let tokens = req.phrase.split(separator: " ").map(String.init)
        var sse = ""
        for t in tokens {
            let data = "{\"content\":\"\(t)\"}"
            sse += "event: token\n"
            sse += "data: \(data)\n\n"
        }
        // Include a final plan snapshot
        let ops = tokens.map { t in "{\"id\":\"\(UUID().uuidString)\",\"kind\":\"token\",\"value\":\"\(t)\"}" }.joined(separator: ",")
        let planJSON = "{\"ops\":[\(ops)]}"
        sse += "event: plan\n"
        sse += "data: \(planJSON)\n\n"
        sse += "event: completion\n"
        sse += "data: {}\n\n"
        return .accepted(.init(body: .text_event_hyphen_stream(HTTPBody(sse))))
    }

    public func applyPlan(_ input: Operations.applyPlan.Input) async throws -> Operations.applyPlan.Output {
        guard case let .json(req) = input.body else {
            let err = Components.Schemas.ErrorResponse(error: "Bad Request", code: "bad_request", correlationId: nil)
            return .badRequest(.init(body: .json(err)))
        }
        let ifm = input.headers.If_hyphen_Match
        guard let result = await state.applyPlanToNotation(sessionId: req.session_id, ifMatch: ifm, plan: req.plan) else {
            let err = Components.Schemas.ErrorResponse(error: "Notation session not found", code: "notation_session_not_found", correlationId: nil)
            return .badRequest(.init(body: .json(err)))
        }
        if result.etagMismatch {
            let conflict = Components.Schemas.Conflict(code: "etag_mismatch", message: "If-Match does not match current ETag", anchors: [])
            let body = Components.Schemas.ApplyPlanResponse(appliedOps: [], conflicts: [conflict], scoreETag: result.newETag)
            return .conflict(.init(body: .json(body)))
        }
        await state.appendJournal(type: "plan_applied", details: [
            "session_id": req.session_id,
            "ops": String(result.appliedOps.count)
        ])
        let body = Components.Schemas.ApplyPlanResponse(appliedOps: result.appliedOps, conflicts: [], scoreETag: result.newETag)
        let headers = Operations.applyPlan.Output.Ok.Headers(ETag: result.newETag)
        return .ok(.init(headers: headers, body: .json(body)))
    }

    // MARK: - Journal
    public func listJournal(_ input: Operations.listJournal.Input) async throws -> Operations.listJournal.Output {
        let items = await state.listJournal(limit: 50, offset: 0)
        let out = Components.Schemas.JournalList(items: items, nextPage: nil)
        return .ok(.init(body: .json(out)))
    }
    public func streamJournal(_ input: Operations.streamJournal.Input) async throws -> Operations.streamJournal.Output {
        let items = await state.listJournal(limit: 50, offset: 0)
        var sse = ""
        for ev in items {
            let id = ev.id ?? UUID().uuidString
            sse += "id: \(id)\n"
            sse += "event: \(ev._type.rawValue)\n"
            let dataObj: [String: String] = ev.details?.additionalProperties ?? [:]
            if let data = try? JSONSerialization.data(withJSONObject: dataObj), let str = String(data: data, encoding: .utf8) {
                sse += "data: \(str)\n\n"
            } else {
                sse += "data: {}\n\n"
            }
        }
        sse += "event: completion\n"
        sse += "data: {}\n\n"
        return .ok(.init(body: .text_event_hyphen_stream(HTTPBody(sse))))
    }

    // MARK: - Notation
    public func createNotationSession(_ input: Operations.createNotationSession.Input) async throws -> Operations.createNotationSession.Output {
        let out = await state.createNotationSession()
        return .created(.init(body: .json(out)))
    }
    public func getNotationSession(_ input: Operations.getNotationSession.Input) async throws -> Operations.getNotationSession.Output {
        if let out = await state.getNotationSession(id: input.path.id) {
            return .ok(.init(body: .json(out)))
        }
        return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
    }
    public func putLilySource(_ input: Operations.putLilySource.Input) async throws -> Operations.putLilySource.Output {
        let id = input.path.id
        let ifm = input.headers.If_hyphen_Match
        let bodyStr: String
        switch input.body {
        case .plainText(let b):
            bodyStr = try await String(collecting: b, upTo: 1<<20)
        }
        guard let result = await state.putLilySource(id: id, ifMatch: ifm, body: bodyStr) else {
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        }
        if result.ok {
            return .ok(.init(headers: .init(ETag: result.newETag)))
        } else {
            return .preconditionFailed(.init())
        }
    }
    public func getLilySource(_ input: Operations.getLilySource.Input) async throws -> Operations.getLilySource.Output {
        let id = input.path.id
        if let (etag, source) = await state.getLilySource(id: id) {
            let headers = Operations.getLilySource.Output.Ok.Headers(ETag: etag)
            return .ok(.init(headers: headers, body: .plainText(HTTPBody(source))))
        }
        let err = Components.Schemas.ErrorResponse(error: "Not Found", code: "not_found", correlationId: nil)
        return .notFound(.init(body: .json(err)))
    }
    public func renderNotation(_ input: Operations.renderNotation.Input) async throws -> Operations.renderNotation.Output {
        let out = Components.Schemas.RenderResponse(ok: true, artifacts: [])
        return .ok(.init(body: .json(out)))
    }

    // MARK: - MIDI (UMP)
    public func sendUMPBatch(_ input: Operations.sendUMPBatch.Input) async throws -> Operations.sendUMPBatch.Output {
        guard case let .json(batch) = input.body else {
            let err = Components.Schemas.ErrorResponse(error: "Bad Request", code: "bad_request", correlationId: nil)
            return .badRequest(.init(body: .json(err)))
        }
        func hexWords(_ s: String) -> [UInt32]? {
            let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            if s.isEmpty || (s.count % 8) != 0 { return nil }
            if !s.unicodeScalars.allSatisfy({ allowed.contains($0) }) { return nil }
            var words: [UInt32] = []
            var i = s.startIndex
            while i < s.endIndex {
                let j = s.index(i, offsetBy: 8)
                let chunk = String(s[i..<j])
                guard let val = UInt32(chunk, radix: 16) else { return nil }
                words.append(val)
                i = j
            }
            return words
        }
        let transport = LoopbackTransport()
        for item in batch.items {
            guard let words = hexWords(item.ump) else {
                let err = Components.Schemas.ErrorResponse(error: "Invalid UMP hex", code: "invalid_ump_hex", correlationId: nil)
                return .badRequest(.init(body: .json(err)))
            }
            try? transport.send(umpWords: words)
            // Persist each item for diagnostics and session record.
            await state.persistUMPEvent(session: input.path.session, jr: item.jr_timestamp, host: item.host_time_ns, ump: item.ump)
        }
        await state.appendJournal(type: "ump_received", details: ["session": input.path.session, "count": String(batch.items.count)])
        return .accepted(.init())
    }

    // MARK: - Screenplay (.fountain)
    public func createScreenplaySession(_ input: Operations.createScreenplaySession.Input) async throws -> Operations.createScreenplaySession.Output {
        let out = await state.createScreenplaySession()
        return .created(.init(body: .json(out)))
    }
    public func putScreenplaySource(_ input: Operations.putScreenplaySource.Input) async throws -> Operations.putScreenplaySource.Output {
        let id = input.path.id
        let ifm = input.headers.If_hyphen_Match
        let bodyStr: String
        switch input.body {
        case .plainText(let b):
            bodyStr = try await String(collecting: b, upTo: 1<<20)
        }
        guard let result = await state.putScreenplaySource(id: id, ifMatch: ifm, body: bodyStr) else {
            return .undocumented(statusCode: 404, OpenAPIRuntime.UndocumentedPayload())
        }
        if result.ok {
            return .ok(.init(headers: .init(ETag: result.newETag)))
        } else {
            return .preconditionFailed(.init())
        }
    }
    public func getScreenplaySource(_ input: Operations.getScreenplaySource.Input) async throws -> Operations.getScreenplaySource.Output {
        let id = input.path.id
        if let (etag, source) = await state.getScreenplaySource(id: id) {
            return .ok(.init(headers: .init(ETag: etag), body: .plainText(HTTPBody(source))))
        }
        let err = Components.Schemas.ErrorResponse(error: "Not Found", code: "not_found", correlationId: nil)
        return .notFound(.init(body: .json(err)))
    }
    public func parseScreenplay(_ input: Operations.parseScreenplay.Input) async throws -> Operations.parseScreenplay.Output {
        let id = input.path.id
        guard let (etag, source) = await state.getScreenplaySource(id: id) else {
            let err = Components.Schemas.ErrorResponse(error: "Not Found", code: "not_found", correlationId: nil)
            return .notFound(.init(body: .json(err)))
        }
        // If a cached parse exists for the same ETag, reuse it.
        if let cached = await state.loadParsedScreenplayModel(id: id), cached.etag == etag {
            await state.appendJournal(type: "parsed", details: ["screenplay_id": id, "cache": "hit"]) // lightweight trace
            let out = Components.Schemas.ScreenplayParseResponse(model: cached.model, warnings: [])
            return .ok(.init(body: .json(out)))
        }
        // Parse, persist with ETag, and return.
        let parsed = ScreenplayParser.parse(id: id, text: source)
        await state.persistParsedScreenplayModel(id: id, etag: etag, model: parsed.model)
        await state.appendJournal(type: "parsed", details: [
            "screenplay_id": id,
            "scenes": String(parsed.model.scenes?.count ?? 0),
            "tags": String(parsed.model.notes?.filter { $0.kind == .tag }.count ?? 0)
        ])
        let out = Components.Schemas.ScreenplayParseResponse(model: parsed.model, warnings: parsed.warnings)
        return .ok(.init(body: .json(out)))
    }
    public func parseScreenplayStream(_ input: Operations.parseScreenplayStream.Input) async throws -> Operations.parseScreenplayStream.Output {
        let id = input.path.id
        guard let (etag, source) = await state.getScreenplaySource(id: id) else {
            let err = Components.Schemas.ErrorResponse(error: "Not Found", code: "not_found", correlationId: nil)
            return .notFound(.init(body: .json(err)))
        }
        // Parse once and emit SSE frames for discovered items.
        let parsed = ScreenplayParser.parse(id: id, text: source)
        var sse = ""
        // ETag hint
        sse += "event: meta\n"
        sse += "data: {\"etag\":\"\(etag)\"}\n\n"
        for sc in parsed.model.scenes ?? [] {
            let obj: [String: Any] = [
                "id": sc.id ?? "",
                "number": sc.number as Any,
                "heading": sc.heading ?? ""
            ]
            if let data = try? JSONSerialization.data(withJSONObject: obj), let str = String(data: data, encoding: .utf8) {
                sse += "event: scene\n"
                sse += "data: \(str)\n\n"
            }
        }
        for bt in parsed.model.beats ?? [] {
            let obj: [String: Any] = [
                "id": bt.id ?? "",
                "scene_id": bt.scene_id ?? "",
                "summary": bt.summary ?? "",
                "line": bt.line as Any
            ]
            if let data = try? JSONSerialization.data(withJSONObject: obj), let str = String(data: data, encoding: .utf8) {
                sse += "event: beat\n"
                sse += "data: \(str)\n\n"
            }
        }
        for nt in parsed.model.notes ?? [] {
            let anchor: [String: Any] = [
                "scene_number": nt.anchor?.scene_number as Any,
                "line": nt.anchor?.line as Any,
            ].compactMapValues { $0 }
            let obj: [String: Any] = [
                "id": nt.id ?? "",
                "kind": nt.kind.rawValue,
                "content": nt.content ?? "",
                "anchor": anchor
            ]
            if let data = try? JSONSerialization.data(withJSONObject: obj), let str = String(data: data, encoding: .utf8) {
                sse += "event: note\n"
                sse += "data: \(str)\n\n"
            }
        }
        sse += "event: completion\n"
        sse += "data: {}\n\n"
        // Persist and journal
        await state.persistParsedScreenplayModel(id: id, etag: etag, model: parsed.model)
        await state.appendJournal(type: "parsed", details: [
            "screenplay_id": id,
            "scenes": String(parsed.model.scenes?.count ?? 0),
            "tags": String(parsed.model.notes?.filter { $0.kind == .tag }.count ?? 0)
        ])
        return .accepted(.init(body: .text_event_hyphen_stream(HTTPBody(sse))))
    }
    public func mapScreenplayCues(_ input: Operations.mapScreenplayCues.Input) async throws -> Operations.mapScreenplayCues.Output {
        let id = input.path.id
        // Load source and parse model (prefer cached model when ETag unchanged)
        guard let (etag, source) = await state.getScreenplaySource(id: id) else {
            let err = Components.Schemas.ErrorResponse(error: "Not Found", code: "not_found", correlationId: nil)
            return .notFound(.init(body: .json(err)))
        }
        let parsedModel: Components.Schemas.ScreenplayModel
        if let cached = await state.loadParsedScreenplayModel(id: id), cached.etag == etag {
            parsedModel = cached.model
        } else {
            let parsed = ScreenplayParser.parse(id: id, text: source)
            parsedModel = parsed.model
            await state.persistParsedScreenplayModel(id: id, etag: etag, model: parsedModel)
        }
        // Map notes(kind: tag) => CuePlan with single token op
        var cues: [Components.Schemas.CuePlan] = []
        for n in parsedModel.notes ?? [] {
            if n.kind == .tag {
                let plan = Components.Schemas.Plan(ops: [
                    .init(id: UUID().uuidString, kind: .token, value: n.content, anchor: nil)
                ], meta: .init(origin: .user, confidence: 1.0, source: "screenplay"))
                let cue = Components.Schemas.CuePlan(cue_id: UUID().uuidString, label: n.content, anchor: n.anchor, plan: plan, links: .init(scene_id: nil, beat_id: nil))
                cues.append(cue)
            }
        }
        await state.persistCues(id: id, cues: cues)
        await state.appendJournal(type: "cue_mapped", details: ["screenplay_id": id, "cues": String(cues.count)])
        let payload = Operations.mapScreenplayCues.Output.Ok.Body.jsonPayload(cues: cues)
        return .ok(.init(body: .json(payload)))
    }
    public func getCueSheet(_ input: Operations.getCueSheet.Input) async throws -> Operations.getCueSheet.Output {
        // Prefer persisted cues when available.
        let id = input.path.id
        let cues = await state.loadCues(id: id) ?? []
        switch input.query.format {
        case .some(.csv):
            var csv = "cue_id,label,scene,line,character,ops\n"
            for c in cues {
                let scene = c.anchor?.scene_number.map(String.init) ?? ""
                let line = c.anchor?.line.map(String.init) ?? ""
                let character = c.anchor?.character ?? ""
                let ops = String(c.plan.ops.count)
                let label = (c.label ?? "").replacingOccurrences(of: ",", with: " ")
                csv += "\(c.cue_id),\(label),\(scene),\(line),\(character),\(ops)\n"
            }
            return .ok(.init(body: .csv(HTTPBody(csv))))
        case .some(.pdf):
            // Build a simple PDF with monospaced cue table.
            let pdf = PDFBuilder().makeCueSheetPDF(cues: cues)
            return .ok(.init(body: .pdf(HTTPBody(pdf))))
        default:
            let out = Components.Schemas.CueSheetResponse(cues: cues)
            return .ok(.init(body: .json(out)))
        }
    }

    // MARK: - UMP Events
    public func listUMPEvents(_ input: Operations.listUMPEvents.Input) async throws -> Operations.listUMPEvents.Output {
        let session = input.path.session
        let limit = input.query.page_lbrack_size_rbrack_ ?? 50
        let offset = input.query.page_lbrack_offset_rbrack_ ?? 0
        let events = await state.listUMPEvents(session: session, limit: limit, offset: offset)
        let items = events.map { e in
            Components.Schemas.UMPEvent(id: e.id, session: e.session, jr_timestamp: e.jr_timestamp, host_time_ns: e.host_time_ns, ump: e.ump, receivedAt: e.receivedAt)
        }
        let out = Components.Schemas.UMPEventList(items: items, nextPage: nil)
        return .ok(.init(body: .json(out)))
    }

    // MARK: - Minimal PDF builder for cue sheets
    struct PDFBuilder {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        }
        func lines(for cues: [Components.Schemas.CuePlan]) -> [String] {
            var out: [String] = ["Cue Sheet"]
            out.append("cue_id    scene line character label")
            for c in cues {
                let scene = c.anchor?.scene_number.map(String.init) ?? ""
                let line = c.anchor?.line.map(String.init) ?? ""
                let ch = c.anchor?.character ?? ""
                let label = c.label ?? ""
                out.append("\(c.cue_id.prefix(8))    \(scene)   \(line)   \(ch)   \(label)")
            }
            return out
        }
        func makeCueSheetPDF(cues: [Components.Schemas.CuePlan]) -> Data {
            // Page size 612x792 (US Letter)
            let pageWidth = 612, pageHeight = 792
            var objects: [Data] = []
            func obj(_ s: String) -> Data { Data(s.utf8) }
            // 1: Catalog
            objects.append(obj("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"))
            // 2: Pages
            objects.append(obj("2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n"))
            // 5: Font
            objects.append(obj("5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n"))
            // 4: Content stream
            let startY = 720
            let dy = 16
            var content = "BT\n/F1 12 Tf\n72 \(startY) Td\n"
            for (idx, l) in lines(for: cues).enumerated() {
                if idx > 0 { content += "0 -\(dy) Td\n" }
                content += "(\(escape(l))) Tj\n"
            }
            content += "ET\n"
            let contentData = Data(content.utf8)
            objects.append(obj("4 0 obj\n<< /Length \(contentData.count) >>\nstream\n"))
            objects.append(contentData)
            objects.append(obj("endstream\nendobj\n"))
            // 3: Page
            objects.append(obj("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(pageWidth) \(pageHeight)] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n"))
            // Assemble with xref
            var output = Data("%PDF-1.4\n".utf8)
            var offsets: [Int] = [0] // object 0 is free
            var current = output.count
            for objData in objects {
                offsets.append(current)
                output.append(objData)
                current = output.count
            }
            let xrefStart = output.count
            var xref = "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
            for off in offsets.dropFirst() {
                xref += String(format: "%010d 00000 n \n", off)
            }
            output.append(Data(xref.utf8))
            let trailer = "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xrefStart)\n%%EOF\n"
            output.append(Data(trailer.utf8))
            return output
        }
    }

    // MARK: - Screenplay → Notation bridge
    public func applyScreenplayCuesToNotation(_ input: Operations.applyScreenplayCuesToNotation.Input) async throws -> Operations.applyScreenplayCuesToNotation.Output {
        let screenplayId = input.path.id
        guard case let .json(req) = input.body else { fatalError("generator ensured json body") }
        let session = req.notation_session_id
        // Load cues (persisted), or map on demand when missing.
        var cues = await state.loadCues(id: screenplayId)
        if cues == nil {
            // Best-effort derive cues from current source.
            if let (_, source) = await state.getScreenplaySource(id: screenplayId) {
                let parsed = ScreenplayParser.parse(id: screenplayId, text: source)
                // Derive simple cues from tags.
                var derived: [Components.Schemas.CuePlan] = []
                for n in parsed.model.notes ?? [] where n.kind == .tag {
                    let plan = Components.Schemas.Plan(ops: [
                        .init(id: UUID().uuidString, kind: .token, value: n.content, anchor: nil)
                    ], meta: .init(origin: .user, confidence: 1.0, source: "screenplay"))
                    let cue = Components.Schemas.CuePlan(cue_id: UUID().uuidString, label: n.content, anchor: n.anchor, plan: plan, links: .init(scene_id: nil, beat_id: nil))
                    derived.append(cue)
                }
                cues = derived
            }
        }
        let allOps: [Components.Schemas.PlanOp] = (cues ?? []).flatMap { $0.plan.ops }
        let aggPlan = Components.Schemas.Plan(ops: allOps, meta: .init(origin: .user, confidence: 1.0, source: "cue-bridge"))
        let ifm = input.headers.If_hyphen_Match
        guard let result = await state.applyPlanToNotation(sessionId: session, ifMatch: ifm, plan: aggPlan) else {
            let err = Components.Schemas.ErrorResponse(error: "Notation session not found", code: "notation_session_not_found", correlationId: nil)
            return .notFound(.init(body: .json(err)))
        }
        if result.etagMismatch {
            let conflict = Components.Schemas.Conflict(code: "etag_mismatch", message: "If-Match does not match current ETag", anchors: [])
            let body = Components.Schemas.ApplyPlanResponse(appliedOps: [], conflicts: [conflict], scoreETag: result.newETag)
            return .conflict(.init(body: .json(body)))
        }
        await state.appendJournal(type: "plan_applied", details: [
            "screenplay_id": screenplayId,
            "session_id": session,
            "ops": String(result.appliedOps.count)
        ])
        let body = Components.Schemas.ApplyPlanResponse(appliedOps: result.appliedOps, conflicts: [], scoreETag: result.newETag)
        let headers = Operations.applyScreenplayCuesToNotation.Output.Ok.Headers(ETag: result.newETag)
        return .ok(.init(headers: headers, body: .json(body)))
    }
}
