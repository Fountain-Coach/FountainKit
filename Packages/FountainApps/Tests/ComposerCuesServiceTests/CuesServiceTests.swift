import XCTest
@testable import composer_cues_service

final class CuesServiceTests: XCTestCase {
    func testPlanAndApplyCue() async throws {
        let handlers = ComposerCuesHandlers()
        let projectId = "proj-1"
        let scoreRange = Components.Schemas.BarSelection(startBar: 5, endBar: 12)
        let req = Components.Schemas.CuePlanRequest(
            scriptSceneId: "scene-1",
            scoreId: "score-1",
            scoreRange: scoreRange,
            beats: [],
            styleHint: "gentle",
            agentNotes: nil
        )
        let planOut = try await handlers.planCuesForSelection(.init(path: .init(projectId: projectId), body: .json(req)))
        guard case let .ok(ok) = planOut, case let .json(plan) = ok.body else {
            XCTFail("Expected OK JSON body"); return
        }
        XCTAssertEqual(plan.cues.count, 1)
        let cuePayload = plan.cues[0]
        XCTAssertEqual(cuePayload.value1.barStart, 5)
        XCTAssertEqual(cuePayload.value1.barEnd, 12)

        // Apply the plan
        let applyReq = Components.Schemas.CueApplyPlanRequest(cues: [cuePayload.value1])
        _ = try await handlers.applyCuePlan(.init(path: .init(projectId: projectId), body: .json(applyReq)))

        let listOut = try await handlers.listProjectCues(.init(path: .init(projectId: projectId)))
        guard case let .ok(listOk) = listOut, case let .json(listBody) = listOk.body else {
            XCTFail("Expected OK JSON body"); return
        }
        XCTAssertEqual(listBody.cues.count, 1)
        XCTAssertEqual(listBody.cues[0].status, .applied)
    }
}

