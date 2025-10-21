import Foundation
import OpenAPIRuntime

actor AudioTalkState {
    struct NotationEntry { var source: String; var eTag: String; var createdAt: Date }
    struct ScreenplayEntry { var source: String; var eTag: String; var createdAt: Date }

    private var dictionary: [String: Components.Schemas.DictionaryItem] = [:]
    private var macros: [String: Components.Schemas.Macro] = [:]
    private var notation: [String: NotationEntry] = [:]
    private var screenplay: [String: ScreenplayEntry] = [:]

    private func newETag() -> String { UUID().uuidString }

    // Dictionary
    func listDictionary(limit: Int = 50, after: String? = nil) -> Components.Schemas.DictionaryList {
        let sorted = dictionary.keys.sorted()
        let startIndex = after.flatMap { sorted.firstIndex(of: $0) }.map { sorted.index(after: $0) } ?? sorted.startIndex
        let slice = sorted[startIndex...].prefix(limit)
        let items = slice.compactMap { dictionary[$0] }
        let next = slice.count == limit ? slice.last : nil
        return .init(items: items, nextPage: next)
    }
    func upsertDictionary(_ req: Components.Schemas.DictionaryUpsertRequest) -> Components.Schemas.DictionaryUpsertResponse {
        var updated = 0
        if let items = req.items {
            for it in items {
                dictionary[it.token] = it
                updated += 1
            }
        }
        return .init(updated: updated)
    }

    // Macros
    func listMacros(limit: Int = 50, after: String? = nil) -> Components.Schemas.MacroList {
        let sorted = macros.keys.sorted()
        let startIndex = after.flatMap { sorted.firstIndex(of: $0) }.map { sorted.index(after: $0) } ?? sorted.startIndex
        let slice = sorted[startIndex...].prefix(limit)
        let items = slice.compactMap { macros[$0] }
        let next = slice.count == limit ? slice.last : nil
        return .init(items: items, nextPage: next)
    }
    func createMacro(id: String, plan: Components.Schemas.Plan) -> Components.Schemas.Macro {
        let m = Components.Schemas.Macro(id: id, state: .proposed, plan: plan, created_at: Date())
        macros[id] = m
        return m
    }
    func promoteMacro(id: String) -> Components.Schemas.Macro? {
        guard var m = macros[id] else { return nil }
        m.state = .approved
        macros[id] = m
        return m
    }

    // Notation
    func createNotationSession() -> Components.Schemas.NotationSession {
        let id = UUID().uuidString
        notation[id] = .init(source: "", eTag: newETag(), createdAt: Date())
        return .init(id: id, created_at: notation[id]!.createdAt)
    }
    func getNotationSession(id: String) -> Components.Schemas.NotationSession? {
        guard let e = notation[id] else { return nil }
        return .init(id: id, created_at: e.createdAt)
    }
    func getLilySource(id: String) -> (etag: String, body: String)? {
        guard let e = notation[id] else { return nil }
        return (e.eTag, e.source)
    }
    func putLilySource(id: String, ifMatch: String?, body: String) -> (ok: Bool, newETag: String)? {
        guard var e = notation[id] else { return nil }
        if let ifm = ifMatch, ifm != e.eTag { return (false, e.eTag) }
        e.source = body
        e.eTag = newETag()
        notation[id] = e
        return (true, e.eTag)
    }

    // Screenplay
    func createScreenplaySession() -> Components.Schemas.ScreenplaySession {
        let id = UUID().uuidString
        screenplay[id] = .init(source: "", eTag: newETag(), createdAt: Date())
        let caps = Components.Schemas.Capabilities(rendering: false, ump_streaming: true, reflection: false)
        return .init(id: id, created_at: screenplay[id]!.createdAt, capabilities: caps)
    }
    func getScreenplaySource(id: String) -> (etag: String, body: String)? {
        guard let e = screenplay[id] else { return nil }
        return (e.eTag, e.source)
    }
    func putScreenplaySource(id: String, ifMatch: String?, body: String) -> (ok: Bool, newETag: String)? {
        guard var e = screenplay[id] else { return nil }
        if let ifm = ifMatch, ifm != e.eTag { return (false, e.eTag) }
        e.source = body
        e.eTag = newETag()
        screenplay[id] = e
        return (true, e.eTag)
    }
}

// Minimal server stubs for the AudioTalk OpenAPI.
// These compile against the Apple Swift OpenAPI Generator protocol and return
// placeholder responses. We will incrementally replace them with real logic.

public struct AudioTalkOpenAPI: APIProtocol, @unchecked Sendable {
    let state: AudioTalkState

    init(state: AudioTalkState) { self.state = state }

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
        // Minimal SSE body
        let sse = "event: completion\ndata: {}\n\n"
        return .accepted(.init(body: .text_event_hyphen_stream(HTTPBody(sse))))
    }

    public func applyPlan(_ input: Operations.applyPlan.Input) async throws -> Operations.applyPlan.Output {
        let etag = UUID().uuidString
        let body = Components.Schemas.ApplyPlanResponse(appliedOps: [], conflicts: [], scoreETag: etag)
        let headers = Operations.applyPlan.Output.Ok.Headers(ETag: etag)
        return .ok(.init(headers: headers, body: .json(body)))
    }

    // MARK: - Journal
    public func listJournal(_ input: Operations.listJournal.Input) async throws -> Operations.listJournal.Output {
        let out = Components.Schemas.JournalList(items: [], nextPage: nil)
        return .ok(.init(body: .json(out)))
    }
    public func streamJournal(_ input: Operations.streamJournal.Input) async throws -> Operations.streamJournal.Output {
        let sse = "event: completion\ndata: {}\n\n"
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
        case .plainText:
            bodyStr = ""
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
        func isValidHex(_ s: String) -> Bool {
            if s.isEmpty || (s.count % 2) != 0 { return false }
            let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            return s.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
        for item in batch.items {
            if !isValidHex(item.ump) {
                let err = Components.Schemas.ErrorResponse(error: "Invalid UMP hex", code: "invalid_ump_hex", correlationId: nil)
                return .badRequest(.init(body: .json(err)))
            }
        }
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
        case .plainText:
            bodyStr = ""
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
        let model = Components.Schemas.ScreenplayModel(scenes: [], beats: [], notes: [], characters: [], arcs: [])
        let out = Components.Schemas.ScreenplayParseResponse(model: model, warnings: [])
        return .ok(.init(body: .json(out)))
    }
    public func parseScreenplayStream(_ input: Operations.parseScreenplayStream.Input) async throws -> Operations.parseScreenplayStream.Output {
        return .undocumented(statusCode: 202, OpenAPIRuntime.UndocumentedPayload())
    }
    public func mapScreenplayCues(_ input: Operations.mapScreenplayCues.Input) async throws -> Operations.mapScreenplayCues.Output {
        let payload = Operations.mapScreenplayCues.Output.Ok.Body.jsonPayload(cues: [])
        return .ok(.init(body: .json(payload)))
    }
    public func getCueSheet(_ input: Operations.getCueSheet.Input) async throws -> Operations.getCueSheet.Output {
        let out = Components.Schemas.CueSheetResponse(cues: [])
        return .ok(.init(body: .json(out)))
    }
}
