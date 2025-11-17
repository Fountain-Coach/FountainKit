import Foundation
import OpenAPIRuntime

/// Minimal in-memory implementation of the Composer Cues service.
public final class ComposerCuesCore: @unchecked Sendable {
    var cuesByProjectId: [String: [Components.Schemas.CueSummary]] = [:]

    public init() {}
}

public final class ComposerCuesHandlers: APIProtocol, @unchecked Sendable {
    public let core = ComposerCuesCore()

    public func listProjectCues(_ input: Operations.listProjectCues.Input) async throws -> Operations.listProjectCues.Output {
        let projectId = input.path.projectId
        let cues = core.cuesByProjectId[projectId] ?? []
        return .ok(.init(body: .json(.init(cues: cues))))
    }

    public func planCuesForSelection(_ input: Operations.planCuesForSelection.Input) async throws -> Operations.planCuesForSelection.Output {
        let projectId = input.path.projectId
        guard case let .json(req) = input.body else {
            return .ok(.init(body: .json(.init(cues: []))))
        }
        let selection = req.scoreRange
        let barStart = selection?.startBar ?? 1
        let barEnd = selection?.endBar ?? max(barStart, barStart + 3)
        let cueId = "cue-\(projectId)-\(barStart)-\(barEnd)"
        let summary = Components.Schemas.CueSummary(
            id: cueId,
            label: "Cue for \(req.scriptSceneId)",
            sceneId: req.scriptSceneId,
            act: 1,
            barStart: barStart,
            barEnd: barEnd,
            status: .proposed,
            styleHint: req.styleHint
        )
        let extra = Components.Schemas.CuePlanResponse.cuesPayloadPayload.Value2Payload(
            confidence: 0.7,
            rationale: "Stub plan based on supplied score range."
        )
        let payload = Components.Schemas.CuePlanResponse.cuesPayloadPayload(
            value1: summary,
            value2: extra
        )
        let response = Components.Schemas.CuePlanResponse(cues: [payload])
        return .ok(.init(body: .json(response)))
    }

    public func reviseCue(_ input: Operations.reviseCue.Input) async throws -> Operations.reviseCue.Output {
        let projectId = input.path.projectId
        let cueId = input.path.cueId
        guard case let .json(req) = input.body else {
            return .undocumented(statusCode: 400, .init())
        }
        var cues = core.cuesByProjectId[projectId] ?? []
        guard let idx = cues.firstIndex(where: { $0.id == cueId }) else {
            return .undocumented(statusCode: 404, .init())
        }
        var cue = cues[idx]
        // Minimal behaviour: treat instructions as a label suffix; ignore keepRange/retargetScene for now.
        let baseLabel = cue.label ?? "Cue"
        let suffix = req.instructions ?? ""
        cue.label = suffix.isEmpty ? baseLabel : baseLabel + " (\(suffix))"
        cues[idx] = cue
        core.cuesByProjectId[projectId] = cues
        return .ok(.init(body: .json(cue)))
    }

    public func applyCuePlan(_ input: Operations.applyCuePlan.Input) async throws -> Operations.applyCuePlan.Output {
        let projectId = input.path.projectId
        guard case let .json(req) = input.body else {
            return .noContent
        }
        var cues = core.cuesByProjectId[projectId] ?? []
        for incoming in req.cues {
            if let idx = cues.firstIndex(where: { $0.id == incoming.id }) {
                var updated = incoming
                updated.status = .applied
                cues[idx] = updated
            } else {
                var applied = incoming
                applied.status = .applied
                cues.append(applied)
            }
        }
        core.cuesByProjectId[projectId] = cues
        return .noContent
    }
}
