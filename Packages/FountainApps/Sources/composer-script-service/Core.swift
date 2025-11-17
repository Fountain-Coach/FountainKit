import Foundation
import OpenAPIRuntime

/// Minimal in-memory implementation of the Composer Script service.
public final class ComposerScriptCore: @unchecked Sendable {
    // For now we host a single script with one act/scene and the sample text.
    public let scriptId: String = "default"

    public let acts: [Components.Schemas.Act]
    public let sceneSlice: Components.Schemas.SceneSlice
    var beatsBySceneKey: [String: [Components.Schemas.Beat]] = [:]
    var state: Components.Schemas.ScriptStatePatch?

    public init() {
        let summary = Components.Schemas.SceneSummary(index: 1, slugline: "INT. OFFICE – DAY")
        self.acts = [
            .init(index: 1, title: "ACT 1", scenes: [summary])
        ]
        let lines: [String] = [
            "INT. OFFICE – DAY",
            "",
            "Bob sits at his desk, staring at",
            "the computer screen. The faint tap-",
            "ping of keys is heard. He stops",
            "and sighs.",
            "",
            "Mary enters, carrying a stack of",
            "papers.",
            "",
            "                     MARY",
            "          How's it going?",
        ]
        self.sceneSlice = .init(
            act: 1,
            scene: 1,
            slugline: "INT. OFFICE – DAY",
            startLine: 1,
            endLine: lines.count,
            text: lines
        )
    }

    func beatsKey(act: Int, scene: Int) -> String { "act\(act)-scene\(scene)" }
}

public final class ComposerScriptHandlers: APIProtocol, @unchecked Sendable {
    public let core = ComposerScriptCore()

    public func getScript(_ input: Operations.getScript.Input) async throws -> Operations.getScript.Output {
        let doc = Components.Schemas.ScriptDocument(
            scriptId: core.scriptId,
            acts: core.acts,
            scene: core.sceneSlice
        )
        return .ok(.init(body: .json(doc)))
    }

    public func getSceneBeats(_ input: Operations.getSceneBeats.Input) async throws -> Operations.getSceneBeats.Output {
        let act = input.query.act
        let scene = input.query.scene
        let key = core.beatsKey(act: act, scene: scene)
        let beats = core.beatsBySceneKey[key] ?? []
        return .ok(.init(body: .json(.init(beats: beats))))
    }

    public func tagSceneBeats(_ input: Operations.tagSceneBeats.Input) async throws -> Operations.tagSceneBeats.Output {
        guard case let .json(req) = input.body else {
            return .ok(.init(body: .json(.init(beats: []))))
        }
        let act = req.act
        let scene = req.scene
        let key = core.beatsKey(act: act, scene: scene)
        // Minimal stub: create a single beat for the entire scene with a mode-specific label.
        let beat = Components.Schemas.Beat(
            id: "beat-\(act)-\(scene)-1",
            lineStart: core.sceneSlice.startLine,
            lineEnd: core.sceneSlice.endLine,
            label: req.mode.rawValue,
            emotionTag: req.hint
        )
        core.beatsBySceneKey[key] = [beat]
        return .ok(.init(body: .json(.init(beats: [beat]))))
    }

    public func setScriptState(_ input: Operations.setScriptState.Input) async throws -> Operations.setScriptState.Output {
        if case let .json(patch) = input.body {
            core.state = patch
        }
        return .noContent
    }
}
