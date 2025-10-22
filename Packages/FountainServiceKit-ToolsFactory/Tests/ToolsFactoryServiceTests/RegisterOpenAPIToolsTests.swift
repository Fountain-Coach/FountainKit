import XCTest
import ToolsFactoryService
import FountainStoreClient
import OpenAPIRuntime

final class RegisterOpenAPIToolsTests: XCTestCase {
    func testRegisterMinimalAudioTalkSpec() async throws {
        let store = FountainStoreClient(client: EmbeddedFountainStoreClient())
        let api = ToolsFactoryOpenAPI(persistence: store)

        // Minimal OpenAPI: servers + two paths (Sendable containers)
        func obj(_ d: [String: (any Sendable)?]) -> (any Sendable) { d }
        func arr(_ a: [(any Sendable)]) -> (any Sendable) { a }
        let specTop: [String: (any Sendable)?] = [
            "openapi": "3.1.0",
            "servers": arr([ obj(["url": "http://localhost:8080/audiotalk/v1"]) ]),
            "paths": obj([
                "/audiotalk/screenplay/sessions": obj([
                    "post": obj(["operationId": "createScreenplaySession", "summary": "Create screenplay"]) ]),
                "/audiotalk/screenplay/{id}/parse": obj([
                    "post": obj(["operationId": "parseScreenplay", "summary": "Parse screenplay"]) ])
            ])
        ]
        let container = try OpenAPIObjectContainer(unvalidatedValue: specTop)
        let input = Operations.register_openapi.Input(
            query: .init(corpusId: "audiotalk"),
            body: .json(.init(additionalProperties: container))
        )
        let out = try await api.register_openapi(input)
        guard case .ok(let ok) = out, case .json(let body) = ok.body else {
            XCTFail("Unexpected response: \(out)")
            return
        }
        XCTAssertNotNil(body.functions)
        XCTAssertGreaterThan(body.functions?.count ?? 0, 0)
        // Verify functions persisted
        let (_, list) = try await store.listFunctions(corpusId: "audiotalk", limit: 100, offset: 0)
        XCTAssertEqual(list.count, body.functions?.count)
        // Check that paths are absolute (start with http)
        for f in list {
            XCTAssertTrue(f.httpPath.hasPrefix("http"))
        }
    }
}
