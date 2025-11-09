import XCTest
import FountainEditorMiniCore
import Teatro

final class FountainEditorRuleToggleTests: XCTestCase {
    private func loadFixture(_ name: String) -> String {
        let path = "Packages/FountainApps/Tests/FountainEditorAlignmentTests/Fixtures/" + name
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    private func anchorsMini(_ text: String, options: FountainEditorMiniCore.ParserOptions) -> [String] {
        let s = FountainEditorMiniCore.parseStructure(text: text, options: options)
        return s.acts.flatMap { $0.scenes.map { $0.anchor } }
    }
    private func anchorsTeatro(_ text: String, rules: RuleSet) -> [String] {
        let parser = FountainParser(rules: rules)
        let nodes = parser.parse(text)
        var anchors: [String] = []
        var act = 0, scene = 0
        func pushAct() { act += 1; scene = 0 }
        func pushScene() { scene += 1; anchors.append("act\(act).scene\(scene)") }
        for n in nodes {
            switch n.type {
            case .section(let level):
                if level == 1 { pushAct() }
                else if level == 2 { if act == 0 { pushAct() }; pushScene() }
            case .sceneHeading:
                if act == 0 { pushAct() }
                pushScene()
            default: continue
            }
        }
        if act == 0 { pushAct() }
        return anchors
    }

    func testSectionsToggle_alignment() {
        let text = loadFixture("simple_sections.fountain")
        // Sections on
        var rules = RuleSet()
        rules.enableSections = true
        var mini = FountainEditorMiniCore.ParserOptions.extended
        mini.acceptSections = true
        XCTAssertEqual(anchorsMini(text, options: mini), anchorsTeatro(text, rules: rules))
        // Sections off
        rules.enableSections = false
        mini.acceptSections = false
        XCTAssertEqual(anchorsMini(text, options: mini), anchorsTeatro(text, rules: rules))
    }

    func testNotesBoneyardSynopsesToggle_noScenesEitherWay() {
        let text = loadFixture("synopses_boneyard_notes.fountain")
        var rules = RuleSet()
        rules.enableNotes = false
        rules.enableBoneyard = false
        rules.enableSynopses = false
        // These toggles should not impact scene count; both sides yield zero scenes
        let mini = FountainEditorMiniCore.ParserOptions.strict
        XCTAssertEqual(anchorsMini(text, options: mini).count, 0)
        XCTAssertEqual(anchorsTeatro(text, rules: rules).count, 0)
    }

    func testStrictSceneHeadingKeywords_alignment() {
        let text = loadFixture("extended1.fountain")
        var rules = RuleSet()
        rules.sceneHeadingKeywords = ["INT.", "EXT."]
        XCTAssertEqual(anchorsMini(text, options: .strict), anchorsTeatro(text, rules: rules))
    }
}
