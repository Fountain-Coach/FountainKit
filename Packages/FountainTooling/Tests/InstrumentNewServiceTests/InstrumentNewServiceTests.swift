import XCTest
import FountainRuntime
@testable import InstrumentNewService

@MainActor
final class InstrumentNewServiceTests: XCTestCase {
    func testRunInstrumentNewDryRunViaHTTPKernel() async throws {
        let kernel = makeInstrumentNewKernel()

        struct RequestBody: Codable {
            let appId: String
            let agentId: String
            let specName: String
            let visual: Bool
            let metalview: Bool
            let noApp: Bool
            let dryRun: Bool
        }

        let body = RequestBody(
            appId: "llm-chat-int",
            agentId: "fountain.coach/agent/llm-chat-int/service",
            specName: "llm-chat-int.yml",
            visual: true,
            metalview: false,
            noApp: true,
            dryRun: true
        )
        let data = try JSONEncoder().encode(body)

        let request = HTTPRequest(
            method: "POST",
            path: "/instrument-new/run",
            headers: ["Content-Type": "application/json"],
            body: data
        )

        let response = try await kernel.handle(request)
        XCTAssertEqual(response.status, 200)

        let decoded = try JSONDecoder().decode(
            Components.Schemas.InstrumentNewResponse.self,
            from: response.body
        )
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.appId, "llm-chat-int")
        XCTAssertEqual(decoded.agentId, "fountain.coach/agent/llm-chat-int/service")
        XCTAssertEqual(decoded.specName, "llm-chat-int.yml")
        XCTAssertEqual(decoded.dryRun, true)
        XCTAssertNotNil(decoded.applied)
    }
}

