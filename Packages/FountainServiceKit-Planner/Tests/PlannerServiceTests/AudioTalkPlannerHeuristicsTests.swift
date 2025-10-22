import XCTest
import PlannerService
import FountainStoreClient
import OpenAPIRuntime

final class AudioTalkPlannerHeuristicsTests: XCTestCase {
    func testHeuristicPlanFromObjective() async throws {
        let store = FountainStoreClient(client: EmbeddedFountainStoreClient())
        let api = PlannerOpenAPI(persistence: store)
        let req = Components.Schemas.UserObjectiveRequest(objective: "parse screenplay id=SID map cues apply to notation notation=NID cue sheet journal ump events session=US")
        let out = try await api.planner_reason(.init(body: .json(req)))
        guard case .ok(let ok) = out, case .json(let plan) = ok.body else { return XCTFail("unexpected response: \(out)") }
        let names = plan.steps.map { $0.name }
        XCTAssertTrue(names.contains("parseScreenplay"))
        XCTAssertTrue(names.contains("mapScreenplayCues"))
        XCTAssertTrue(names.contains("getCueSheet"))
        XCTAssertTrue(names.contains("applyScreenplayCuesToNotation"))
        XCTAssertTrue(names.contains("listJournal"))
        XCTAssertTrue(names.contains("listUMPEvents"))
        // Check one arguments container
        if let apply = plan.steps.first(where: { $0.name == "applyScreenplayCuesToNotation" }) {
            let dict = apply.arguments.additionalProperties.value
            XCTAssertEqual(dict["id"] as? String, "SID")
            XCTAssertEqual(dict["notation_session_id"] as? String, "NID")
        }
    }
}

