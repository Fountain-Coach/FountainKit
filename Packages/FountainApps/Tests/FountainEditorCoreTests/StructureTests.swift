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
    }

    func testETag_stability() {
        let a = FountainEditorCore.computeETag(for: "Hello")
        let b = FountainEditorCore.computeETag(for: "Hello")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 8)
    }
}

