import XCTest
import FountainEditorMiniCore

final class EditorCoreTests: XCTestCase {
    func testParseStructure_withSectionsActScenes() {
        let text = """
        Title: Test

        # Act 1
        ## Scene 1
        INT. ROOM — DAY

        ## Scene 2
        EXT. STREET — NIGHT
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 2)
        XCTAssertTrue(s.etag.count == 8)
    }
    func testParseStructure_scenesOnly() {
        let text = """
        Title: X

        INT. ROOM — DAY

        EXT. FIELD — DAY
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 2)
        XCTAssertEqual(s.acts[0].scenes[0].anchor, "act1.scene1")
        XCTAssertEqual(s.acts[0].scenes[1].anchor, "act1.scene2")
    }

    func testETag_stability() {
        let a = FountainEditorMiniCore.computeETag(for: "Hello")
        let b = FountainEditorMiniCore.computeETag(for: "Hello")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 8)
    }

    func testPlacementsCRUD_InMemoryCore() {
        var pc = PlacementsMiniCore()
        let p = pc.add(anchor: "act1.scene1", instrumentId: "i1", order: 1)
        XCTAssertEqual(pc.list(anchor: "act1.scene1").count, 1)
        XCTAssertTrue(pc.update(id: p.id, anchor: "act1.scene1", order: 2))
        XCTAssertEqual(pc.list(anchor: "act1.scene1").first?.order, 2)
        XCTAssertTrue(pc.remove(id: p.id, anchor: "act1.scene1"))
        XCTAssertEqual(pc.list(anchor: "act1.scene1").count, 0)
    }

    func testINTEXTVariants_detected_whenNoSections() {
        let text = """
        INT. KITCHEN — MORNING
        Some action
        EXT. GARDEN — DAY
        More action
        I/E. PORCH — EVENING
        Even more action
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 3)
        XCTAssertEqual(s.acts[0].scenes.map { $0.anchor }, ["act1.scene1","act1.scene2","act1.scene3"])
    }

    func testNoFalsePositiveOnDialogue() {
        let text = """
        JOHN
        INTERNAL monologue and EXTREMELY loud talk.
        This should not create scenes.
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 0)
    }

    func testTransitionsAndCharacterContdIgnored() {
        let text = """
        FADE IN:
        JOHN (CONT'D)
        Let's continue.
        CUT TO:
        SMASH TO:
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 0)
    }

    func testSlugVariantsNumberedAndHyphenated() {
        let text = """
        1. INT. ROOM - DAY
        text
        ext/int. CAR - NIGHT
        text
        INT - GARAGE - DAY
        text
        """
        let s = FountainEditorMiniCore.parseStructure(text: text, options: .extended)
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.count, 3)
    }

    func testStrictModeRejectsNumberedSlugsAndVariants() {
        let text = """
        1. INT. ROOM - DAY
        text
        I/E. PORCH - EVENING
        """
        let strict = FountainEditorMiniCore.parseStructure(text: text, options: .strict)
        XCTAssertEqual(strict.acts.count, 1)
        XCTAssertEqual(strict.acts[0].scenes.count, 0)
        let extended = FountainEditorMiniCore.parseStructure(text: text, options: .extended)
        XCTAssertEqual(extended.acts[0].scenes.count, 2)
    }

    func testToggle_acceptNumberedSlugs_onlyWhenEnabled() {
        let text = """
        1. INT. ROOM - DAY
        text
        INT. HALL - NIGHT
        """
        var opts = FountainEditorMiniCore.ParserOptions.strict
        opts.acceptNumberedSlugs = false
        let a = FountainEditorMiniCore.parseStructure(text: text, options: opts)
        XCTAssertEqual(a.acts.first?.scenes.count, 1)
        opts.acceptNumberedSlugs = true
        let b = FountainEditorMiniCore.parseStructure(text: text, options: opts)
        XCTAssertEqual(b.acts.first?.scenes.count, 2)
    }

    func testToggle_acceptSlugVariants_controlsIEScenes() {
        let text = """
        I/E. PORCH - EVENING
        INT. DEN - NIGHT
        """
        var opts = FountainEditorMiniCore.ParserOptions.strict
        opts.acceptSlugVariants = false
        let a = FountainEditorMiniCore.parseStructure(text: text, options: opts)
        XCTAssertEqual(a.acts.first?.scenes.count, 1)
        opts.acceptSlugVariants = true
        let b = FountainEditorMiniCore.parseStructure(text: text, options: opts)
        XCTAssertEqual(b.acts.first?.scenes.count, 2)
    }

    func testToggle_acceptSections_falseTreatsSectionsAsText() {
        let text = """
        # Act 1
        ## Scene 1
        INT. ROOM - DAY
        """
        var opts = FountainEditorMiniCore.ParserOptions.extended
        opts.acceptSections = false
        // With sections off, we should still detect the slug scene
        let s = FountainEditorMiniCore.parseStructure(text: text, options: opts)
        XCTAssertEqual(s.acts.first?.scenes.count, 1)
        XCTAssertEqual(s.acts.first?.scenes.first?.anchor, "act1.scene1")
    }

    func testToggle_gateSlugsWhenSectionsPresent_falseAllowsMixed() {
        let text = """
        # Act 1
        INT. SLUG SCENE - DAY
        ## Section Scene
        """
        var opts = FountainEditorMiniCore.ParserOptions.extended
        opts.gateSlugsWhenSectionsPresent = false
        let s = FountainEditorMiniCore.parseStructure(text: text, options: opts)
        XCTAssertEqual(s.acts.first?.scenes.count, 2)
    }

    func testActsImplicitWhenSectionsPresent_noActSplit() {
        let text = """
        INT. ONE
        text
        # Act 2
        ## Scene A
        text
        ## Scene B
        text
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        // Minimal parser groups everything into one implicit act when sections exist.
        XCTAssertEqual(s.acts.count, 1)
        XCTAssertEqual(s.acts[0].scenes.map { $0.anchor }, ["act1.scene1","act1.scene2"]) 
    }

    func testSlugCaseInsensitivityAndExtraSpaces() {
        let text = """
          ext/int.   ALLEY - night
        Some action
          est. Plaza - Day
        Text
        """
        let s = FountainEditorMiniCore.parseStructure(text: text)
        XCTAssertEqual(s.acts.first?.scenes.count, 2)
    }

    func testWeakETagNormalizationAccepted() {
        let e = FountainEditorMiniCore.computeETag(for: "x")
        XCTAssertTrue(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: e, header: "W/\"\(e)\""))
    }

    func testIfMatchNormalizationTrimsWhitespace() {
        let e = FountainEditorMiniCore.computeETag(for: "y")
        XCTAssertTrue(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: e, header: "  \"\(e)\"  "))
    }

    func testMappingValidationAllowsNilValues() {
        XCTAssertNoThrow(try FountainEditorMiniValidation.validateMapping(channels: nil, group: nil, filters: nil))
    }

    func testPlacementsUpdateBusAndRemoveMissingFalse() {
        var pc = PlacementsMiniCore()
        let p = pc.add(anchor: "act1.scene1", instrumentId: "i2", order: nil, bus: "A")
        XCTAssertTrue(pc.update(id: p.id, anchor: "act1.scene1", order: nil, bus: "B"))
        XCTAssertEqual(pc.list(anchor: "act1.scene1").first?.bus, "B")
        XCTAssertFalse(pc.remove(id: UUID(), anchor: "act1.scene1"))
        XCTAssertEqual(pc.list(anchor: "missing").count, 0)
    }
}

final class MiniValidationTests: XCTestCase {
    func testIfMatchSatisfied_acceptsExactAndWildcard() {
        let etag = FountainEditorMiniCore.computeETag(for: "Hello")
        XCTAssertTrue(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: etag, header: etag))
        XCTAssertTrue(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: etag, header: "\"\(etag)\""))
        XCTAssertTrue(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: etag, header: "*"))
        XCTAssertFalse(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: etag, header: "deadbeef"))
        XCTAssertFalse(FountainEditorMiniValidation.ifMatchSatisfied(currentETag: etag, header: nil))
    }
    func testValidateMapping_enforcesRangesAndFilters() {
        XCTAssertNoThrow(try FountainEditorMiniValidation.validateMapping(channels: [1,16], group: 0, filters: ["cv2","m1"]))
        XCTAssertThrowsError(try FountainEditorMiniValidation.validateMapping(channels: [0], group: 0, filters: nil))
        XCTAssertThrowsError(try FountainEditorMiniValidation.validateMapping(channels: [1], group: 16, filters: nil))
        XCTAssertThrowsError(try FountainEditorMiniValidation.validateMapping(channels: [1], group: 0, filters: ["oops"]))
    }
}
