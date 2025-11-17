import Foundation
import OpenAPIRuntime

/// Minimal in-memory implementation of the Composer Score service.
/// State is process-local; persistence into FountainStore can be added later.
public final class ComposerScoreCore: @unchecked Sendable {
    var states: [String: Components.Schemas.ScoreState] = [:]
    var cuesByScoreId: [String: [Components.Schemas.Cue]] = [:]

    public init() {}

    public func state(for scoreId: String) -> Components.Schemas.ScoreState {
        if let existing = states[scoreId] { return existing }
        let initial = Components.Schemas.ScoreState(
            page: 1,
            zoom: 1.0,
            selection: nil,
            annotationsVisible: false,
            cueFocusId: nil
        )
        states[scoreId] = initial
        return initial
    }
}

public final class ComposerScoreHandlers: APIProtocol, @unchecked Sendable {
    public let core = ComposerScoreCore()

    // Score state
    public func getScoreState(_ input: Operations.getScoreState.Input) async throws -> Operations.getScoreState.Output {
        let scoreId = input.path.scoreId
        let state = core.state(for: scoreId)
        return .ok(.init(body: .json(state)))
    }

    public func setScoreState(_ input: Operations.setScoreState.Input) async throws -> Operations.setScoreState.Output {
        let scoreId = input.path.scoreId
        var state = core.state(for: scoreId)
        if case let .json(patch) = input.body {
            if let page = patch.page { state.page = page }
            if let zoom = patch.zoom { state.zoom = zoom }
            if let selection = patch.selection {
                state.selection = selection
            }
            if let annotationsVisible = patch.annotationsVisible {
                state.annotationsVisible = annotationsVisible
            }
            if let cueFocusId = patch.cueFocusId {
                state.cueFocusId = cueFocusId
            }
        }
        core.states[scoreId] = state
        return .noContent
    }

    // Cues
    public func listScoreCues(_ input: Operations.listScoreCues.Input) async throws -> Operations.listScoreCues.Output {
        let scoreId = input.path.scoreId
        let cues = core.cuesByScoreId[scoreId] ?? []
        return .ok(.init(body: .json(.init(cues: cues))))
    }

    public func proposeCuesForScene(_ input: Operations.proposeCuesForScene.Input) async throws -> Operations.proposeCuesForScene.Output {
        let scoreId = input.path.scoreId
        guard case let .json(req) = input.body else {
            return .ok(.init(body: .json(.init(cues: []))))
        }
        // Minimal heuristic: propose a single cue spanning bars 1–4 or the current selection.
        let baseState = core.state(for: scoreId)
        let selection = baseState.selection
        let startBar = selection?.startBar ?? 1
        let endBar = selection?.endBar ?? max(startBar, startBar + 3)
        let cueId = "cue_\(scoreId)_\(startBar)_\(endBar)"
        let summary = Components.Schemas.Cue(
            id: cueId,
            label: "Cue for \(req.scriptSceneId)",
            sceneId: req.scriptSceneId,
            act: req.act,
            barStart: startBar,
            barEnd: endBar,
            styleHint: req.styleHint
        )
        let extra = Components.Schemas.CueProposalResponse.cuesPayloadPayload.Value2Payload(
            confidence: 0.7,
            rationale: "Minimal stub proposal based on current selection."
        )
        let payload = Components.Schemas.CueProposalResponse.cuesPayloadPayload(
            value1: summary,
            value2: extra
        )
        let response = Components.Schemas.CueProposalResponse(cues: [payload])
        return .ok(.init(body: .json(response)))
    }

    public func updateCueSpan(_ input: Operations.updateCueSpan.Input) async throws -> Operations.updateCueSpan.Output {
        let scoreId = input.path.scoreId
        let cueId = input.path.cueId
        guard case let .json(req) = input.body else {
            return .noContent
        }
        var cues = core.cuesByScoreId[scoreId] ?? []
        if let idx = cues.firstIndex(where: { $0.id == cueId }) {
            var cue = cues[idx]
            if let barStart = req.barStart { cue.barStart = barStart }
            if let barEnd = req.barEnd { cue.barEnd = barEnd }
            if let label = req.label { cue.label = label }
            if let styleHint = req.styleHint { cue.styleHint = styleHint }
            cues[idx] = cue
        }
        core.cuesByScoreId[scoreId] = cues
        return .noContent
    }
}
