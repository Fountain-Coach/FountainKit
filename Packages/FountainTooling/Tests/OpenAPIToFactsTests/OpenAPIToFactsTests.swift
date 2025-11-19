import XCTest
@testable import openapi_to_facts

final class OpenAPIToFactsTests: XCTestCase {
    func testNormalizeIdAndMakeId() {
        XCTAssertEqual(OpenAPIToFacts.normalizeId("Service Name/With Spaces"), "service-name-with-spaces")
        let id = OpenAPIToFacts.makeId(svc: "svc", method: "get", path: "/v1/items/{id}")
        XCTAssertEqual(id, "get.v1.items.id")
    }

    func testIsAllowedAsTool() {
        XCTAssertTrue(OpenAPIToFacts.isAllowedAsTool(["x-fountain.allow-as-tool": true]))
        XCTAssertTrue(OpenAPIToFacts.isAllowedAsTool(["x-fountain.allow-as-tool": "true"]))
        XCTAssertFalse(OpenAPIToFacts.isAllowedAsTool([:]))
    }

    func testMergeParamsConcatenatesArrays() {
        let a: [Any] = ["a"]
        let b: [Any] = ["b", "c"]
        let merged = OpenAPIToFacts.mergeParams(a, b)
        XCTAssertEqual(merged.count, 3)
    }

    func testMakeFactsBuildsFunctionBlocksForJsonOperation() throws {
        let openapi: [String: Any] = [
            "info": ["title": "Test Service"],
            "paths": [
                "/items": [
                    "get": [
                        "operationId": "listItems",
                        "x-fountain.allow-as-tool": true,
                        "responses": [
                            "200": [
                                "description": "OK",
                                "content": [
                                    "application/json": [
                                        "schema": [
                                            "type": "object",
                                            "properties": [
                                                "items": [
                                                    "type": "array",
                                                    "items": [
                                                        "type": "string"
                                                    ]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let facts = try OpenAPIToFacts.makeFacts(openapi: openapi, allowToolsOnly: true)
        XCTAssertEqual(facts["protocol"] as? String, "midi-ci-pe")

        let blocks = facts["functionBlocks"] as? [[String: Any]]
        XCTAssertNotNil(blocks)
        XCTAssertEqual(blocks?.first?["name"] as? String, "Test Service")

        let props = blocks?.first?["properties"] as? [[String: Any]]
        XCTAssertEqual(props?.count, 1)
        let prop = props?.first
        XCTAssertEqual(prop?["id"] as? String, "listitems")

        let mapsTo = prop?["mapsTo"] as? [String: Any]
        let openapiMap = mapsTo?["openapi"] as? [String: Any]
        XCTAssertEqual(openapiMap?["method"] as? String, "GET")
        XCTAssertEqual(openapiMap?["path"] as? String, "/items")

        let descriptor = prop?["descriptor"] as? [String: Any]
        let response = descriptor?["response"] as? [String: Any]
        XCTAssertEqual(response?["contentType"] as? String, "application/json")
        XCTAssertEqual(response?["contentTypes"] as? [String], ["application/json"])
    }
}

