import XCTest
@testable import OpenAPICurator

final class OpenAPICuratorTests: XCTestCase {
    func testParserMergesOperationsAndExtensions() {
        let spec1 = Spec(
            operations: ["opA", "opB"],
            extensions: [
                "opA": ["x-fountain.visibility": "public"],
                "opB": ["x-fountain.visibility": "internal"]
            ]
        )
        let spec2 = Spec(
            operations: ["opC"],
            extensions: [
                "opC": ["x-fountain.visibility": "public", "x-fountain.reason": "test"]
            ]
        )

        let api = Parser.parse([spec1, spec2])
        XCTAssertEqual(api.operations, ["opA", "opB", "opC"])
        XCTAssertEqual(api.extensions["opA"]?["x-fountain.visibility"], "public")
        XCTAssertEqual(api.extensions["opB"]?["x-fountain.visibility"], "internal")
        XCTAssertEqual(api.extensions["opC"]?["x-fountain.reason"], "test")
    }

    func testResolverNormalizesWhitespace() {
        let api = OpenAPI(operations: [" opA ", "\topB\n"], extensions: [:])
        let normalized = Resolver.normalize(api)
        XCTAssertEqual(normalized.operations, ["opA", "opB"])
    }

    func testCollisionResolverRenamesAndPreservesExtensions() {
        let api = OpenAPI(
            operations: ["op", "op"],
            extensions: [
                "op": ["x-fountain.visibility": "public"]
            ]
        )
        let (deduped, collisions) = CollisionResolver.resolve(api)
        XCTAssertEqual(deduped.operations.count, 2)
        XCTAssertEqual(deduped.operations[0], "op")
        XCTAssertEqual(deduped.operations[1], "op_1")
        XCTAssertEqual(collisions, ["op"])
        XCTAssertNil(deduped.extensions["op"])
        XCTAssertEqual(deduped.extensions["op_1"]?["x-fountain.visibility"], "public")
    }

    func testRulesEngineAppliesRenamesAndVisibilityAndAllowDenyLists() {
        let api = OpenAPI(
            operations: ["getFoo", "postBar", "deleteBaz"],
            extensions: [
                "getFoo": [
                    "x-fountain.visibility": "public",
                    "x-fountain.allow-as-tool": "true",
                    "x-fountain.reason": "test"
                ]
            ]
        )
        let rules = Rules(
            renames: ["getFoo": "getFooRenamed"],
            allowlist: ["getFooRenamed", "deleteBaz"],
            denylist: ["deleteBaz"]
        )

        let (ruled, applied, truth) = RulesEngine.apply(rules, to: api)

        XCTAssertEqual(ruled.operations, ["getFooRenamed"])
        XCTAssertTrue(applied.contains("getFoo->getFooRenamed"))
        XCTAssertTrue(applied.contains("x-fountain.visibility=public"))
        XCTAssertTrue(applied.contains("x-fountain.allow-as-tool=true"))
        XCTAssertTrue(applied.contains("x-fountain.reason=test"))
        XCTAssertTrue(applied.contains("deny:deleteBaz"))

        let t = truth["getFooRenamed"]
        XCTAssertEqual(t?.visibility, "public")
        XCTAssertEqual(t?.allowAsTool, true)
        XCTAssertEqual(t?.reason, "test")
    }

    func testCurateEndToEnd() {
        let spec = Spec(
            operations: [" opA ", "opA", "opB"],
            extensions: [
                "opA": ["x-fountain.visibility": "public"]
            ]
        )
        let rules = Rules(
            renames: ["opB": "opBRenamed"],
            allowlist: [],
            denylist: []
        )

        let (curated, report) = curate(specs: [spec], rules: rules)
        XCTAssertEqual(Set(curated.operations), Set(["opA", "opA_1", "opBRenamed"]))
        XCTAssertTrue(report.collisions.contains("opA"))
        XCTAssertTrue(report.appliedRules.contains("x-fountain.visibility=public"))
        XCTAssertNotNil(report.truthTable["opA"])
    }
}
