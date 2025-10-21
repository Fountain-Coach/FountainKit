import Foundation
import OpenAPIRuntime

// Minimal server stubs for the AudioTalk OpenAPI.
// These compile against the Apple Swift OpenAPI Generator protocol and return
// placeholder responses. We will incrementally replace them with real logic.

public struct AudioTalkOpenAPI: APIProtocol, @unchecked Sendable {

    public init() {}

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
        return .created(.init(body: .json(out)))
    }

    // MARK: - Dictionary
    public func listDictionary(_ input: Operations.listDictionary.Input) async throws -> Operations.listDictionary.Output {
        let out = Components.Schemas.DictionaryList(items: [], nextPage: nil)
        return .ok(.init(body: .json(out)))
    }

    public func upsertDictionary(_ input: Operations.upsertDictionary.Input) async throws -> Operations.upsertDictionary.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    // MARK: - Macros
    public func listMacros(_ input: Operations.listMacros.Input) async throws -> Operations.listMacros.Output {
        let out = Components.Schemas.MacroList(items: [], nextPage: nil)
        return .ok(.init(body: .json(out)))
    }

    public func createMacro(_ input: Operations.createMacro.Input) async throws -> Operations.createMacro.Output {
        return .undocumented(statusCode: 201, OpenAPIRuntime.UndocumentedPayload())
    }

    public func promoteMacro(_ input: Operations.promoteMacro.Input) async throws -> Operations.promoteMacro.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    // MARK: - Intent
    public func parseIntent(_ input: Operations.parseIntent.Input) async throws -> Operations.parseIntent.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func parseIntentStream(_ input: Operations.parseIntentStream.Input) async throws -> Operations.parseIntentStream.Output {
        // SSE stub
        return .undocumented(statusCode: 202, OpenAPIRuntime.UndocumentedPayload())
    }

    public func applyPlan(_ input: Operations.applyPlan.Input) async throws -> Operations.applyPlan.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    // MARK: - Journal
    public func listJournal(_ input: Operations.listJournal.Input) async throws -> Operations.listJournal.Output {
        let out = Components.Schemas.JournalList(items: [], nextPage: nil)
        return .ok(.init(body: .json(out)))
    }
    public func streamJournal(_ input: Operations.streamJournal.Input) async throws -> Operations.streamJournal.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    // MARK: - Notation
    public func createNotationSession(_ input: Operations.createNotationSession.Input) async throws -> Operations.createNotationSession.Output {
        let out = Components.Schemas.NotationSession(id: UUID().uuidString, created_at: Date())
        return .created(.init(body: .json(out)))
    }
    public func getNotationSession(_ input: Operations.getNotationSession.Input) async throws -> Operations.getNotationSession.Output {
        let out = Components.Schemas.NotationSession(id: input.path.id, created_at: Date())
        return .ok(.init(body: .json(out)))
    }
    public func putLilySource(_ input: Operations.putLilySource.Input) async throws -> Operations.putLilySource.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }
    public func getLilySource(_ input: Operations.getLilySource.Input) async throws -> Operations.getLilySource.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }
    public func renderNotation(_ input: Operations.renderNotation.Input) async throws -> Operations.renderNotation.Output {
        let out = Components.Schemas.RenderResponse(ok: true, artifacts: [])
        return .ok(.init(body: .json(out)))
    }

    // MARK: - MIDI (UMP)
    public func sendUMPBatch(_ input: Operations.sendUMPBatch.Input) async throws -> Operations.sendUMPBatch.Output {
        return .undocumented(statusCode: 202, OpenAPIRuntime.UndocumentedPayload())
    }

    // MARK: - Screenplay (.fountain)
    public func createScreenplaySession(_ input: Operations.createScreenplaySession.Input) async throws -> Operations.createScreenplaySession.Output {
        let caps = Components.Schemas.Capabilities(rendering: false, ump_streaming: true, reflection: false)
        let out = Components.Schemas.ScreenplaySession(id: UUID().uuidString, created_at: Date(), capabilities: caps)
        return .created(.init(body: .json(out)))
    }
    public func putScreenplaySource(_ input: Operations.putScreenplaySource.Input) async throws -> Operations.putScreenplaySource.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }
    public func getScreenplaySource(_ input: Operations.getScreenplaySource.Input) async throws -> Operations.getScreenplaySource.Output {
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
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
