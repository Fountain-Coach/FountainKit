import XCTest
@testable import fountain_editor_service_core

final class StructureTests: XCTestCase {
    func testParseStructure_withSections() {
        let text = """
        Title: Test

        # Act 1
        ## Scene 1
        INT. ROOM — DAY

        ## Scene 2
        EXT. STREET — NIGHT
        """
        let s = FountainEditorCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 2)
        XCTAssertTrue(s.etag.count == 8)
    }

    func testParseStructure_sceneHeadingsOnly() {
        let text = """
        Title: X

        INT. ROOM — DAY

        EXT. FIELD — DAY
        """
        let s = FountainEditorCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1) // implicit Act I
        XCTAssertEqual(s.acts[0].scenes.count, 2)
        XCTAssertEqual(s.acts[0].scenes[0].anchor, "act1.scene1")
        XCTAssertEqual(s.acts[0].scenes[1].anchor, "act1.scene2")
    }

    func testETag_stability() {
        let a = FountainEditorCore.computeETag(for: "Hello")
        let b = FountainEditorCore.computeETag(for: "Hello")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 8)
    }
}

final class PlacementsCoreTests: XCTestCase {
    func testPlacementsCRUDByAnchor() {
        var pc = PlacementsCore()
        let p1 = pc.add(anchor: "act1.scene1", instrumentId: "instA", order: 1)
        XCTAssertEqual(pc.list(anchor: "act1.scene1").count, 1)
        XCTAssertTrue(pc.update(id: p1.id, anchor: "act1.scene1", order: 2))
        XCTAssertEqual(pc.list(anchor: "act1.scene1").first?.order, 2)
        XCTAssertTrue(pc.remove(id: p1.id, anchor: "act1.scene1"))
        XCTAssertEqual(pc.list(anchor: "act1.scene1").count, 0)
    }
}

final class ETagAndMappingTests: XCTestCase {
    func testIfMatchSatisfied_acceptsExactAndWildcard() {
        let etag = FountainEditorCore.computeETag(for: "Hello")
        XCTAssertTrue(FountainEditorValidation.ifMatchSatisfied(currentETag: etag, header: etag))
        XCTAssertTrue(FountainEditorValidation.ifMatchSatisfied(currentETag: etag, header: "\"\(etag)\""))
        XCTAssertTrue(FountainEditorValidation.ifMatchSatisfied(currentETag: etag, header: "*"))
        XCTAssertFalse(FountainEditorValidation.ifMatchSatisfied(currentETag: etag, header: "deadbeef"))
        XCTAssertFalse(FountainEditorValidation.ifMatchSatisfied(currentETag: etag, header: nil))
    }

    func testValidateMapping_enforcesRangesAndFilters() {
        XCTAssertNoThrow(try FountainEditorValidation.validateMapping(channels: [1,16], group: 0, filters: ["cv2","m1"]))
        XCTAssertThrowsError(try FountainEditorValidation.validateMapping(channels: [0], group: 0, filters: nil))
        XCTAssertThrowsError(try FountainEditorValidation.validateMapping(channels: [1], group: 16, filters: nil))
        XCTAssertThrowsError(try FountainEditorValidation.validateMapping(channels: [1], group: 0, filters: ["oops"]))
    }
}
