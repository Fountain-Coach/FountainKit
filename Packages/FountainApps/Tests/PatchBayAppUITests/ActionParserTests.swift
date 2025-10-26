import XCTest
@testable import patchbay_app

@MainActor
final class ActionParserTests: XCTestCase {
    func testParseSingleCreateLinkJSON() throws {
        let json = """
        {"service":"patchbay-service","operationId":"createLink","body":{"kind":"property","property":{"from":"A.out","to":"B.in","direction":"a_to_b"}}}
        """
        let actions = OpenAPIActionParser.parse(fromText: json)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.service, "patchbay-service")
        XCTAssertEqual(actions.first?.operationId, "createLink")
    }

    func testParseArrayJSON() throws {
        let json = """
        [
          {"service":"patchbay-service","operationId":"createLink","body":{"kind":"property","property":{"from":"A.out","to":"B.in","direction":"a_to_b"}}},
          {"service":"patchbay-service","operationId":"deleteLink","pathParams":{"id":"link-1"}}
        ]
        """
        let actions = OpenAPIActionParser.parse(fromText: json)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[1].operationId, "deleteLink")
    }
}

