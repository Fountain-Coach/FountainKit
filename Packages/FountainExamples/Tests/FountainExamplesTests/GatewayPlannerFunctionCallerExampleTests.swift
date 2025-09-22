import XCTest
@testable import FountainExamples

final class GatewayPlannerFunctionCallerExampleTests: XCTestCase {
    func testGatewayPlannerFunctionCallerFlow() async throws {
        let example = GatewayPlannerFunctionCallerExample()
        let seeded = try await example.seedDemoData(functionId: "integration-test")
        let outcome = try await example.runDemoFlow(objective: "Integration coverage")

        XCTAssertEqual(outcome.plan.objective, "Integration coverage")
        XCTAssertFalse(outcome.functions.functions.isEmpty)
        XCTAssertEqual(outcome.functions.functions.first?.function_id, seeded.functionId)
        XCTAssertEqual(outcome.execution.results.first?.step, seeded.name)
        XCTAssertEqual(outcome.execution.results.first?.output, "ok")
    }
}
