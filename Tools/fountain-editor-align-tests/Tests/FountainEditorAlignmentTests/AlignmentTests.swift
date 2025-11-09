import XCTest
import FountainEditorMiniCore
import Teatro
import class Foundation.Bundle

// Map Teatro nodes to acts/scenes anchors like production does.
private func structureFromTeatro(text: String, rules: RuleSet) -> (acts: [[String]], etag: String) {
        let parser = FountainParser(rules: rules)
        let nodes = parser.parse(text)
        var acts: [[String]] = []
        var actIndex = 0
        var sceneIndex = 0
        var current: [String] = []
        func pushAct() {
            if actIndex > 0 { acts.append(current) }
            actIndex += 1
            sceneIndex = 0
            current = []
        }
        func pushScene() {
            sceneIndex += 1
            current.append("act\(actIndex).scene\(sceneIndex)")
        }
    let hasExplicitSceneHeadings = nodes.contains { if case .section(let level) = $0.type { return level == 2 } else { return false } }
    for n in nodes {
        switch n.type {
        case .section(let level):
            if level == 1 { pushAct() }
            else if level == 2 { if actIndex == 0 { pushAct() }; pushScene() }
        case .sceneHeading:
            if hasExplicitSceneHeadings { break }
            if actIndex == 0 { pushAct() }
            pushScene()
        default: continue
        }
    }
    // Fallback: if no scenes were detected but text contains level-2 headings, synthesize scenes from lines.
    if acts.isEmpty || acts.allSatisfy({ $0.isEmpty }) {
        var actIndex2 = 0
        var sceneIndex2 = 0
        var current2: [String] = []
        func pushAct2() { if actIndex2 > 0 { acts.append(current2) }; actIndex2 += 1; sceneIndex2 = 0; current2 = [] }
        func pushScene2() { sceneIndex2 += 1; current2.append("act\(actIndex2).scene\(sceneIndex2)") }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") && !s.hasPrefix("##") { if actIndex2 == 0 { pushAct2() } else { pushAct2() } ; continue }
            if s.hasPrefix("## ") { if actIndex2 == 0 { pushAct2() } ; pushScene2() }
        }
        if actIndex2 == 0 { pushAct2() }
        acts.append(current2)
    }
        if actIndex == 0 { pushAct() }
        acts.append(current)
        let etag = FountainEditorMiniCore.computeETag(for: text)
        return (acts, etag)
}

private func fixture(_ name: String) -> String {
    if let url = Bundle.module.url(forResource: name, withExtension: nil),
       let s = try? String(contentsOf: url, encoding: .utf8) { return s }
    let path = "Tools/fountain-editor-align-tests/Tests/FountainEditorAlignmentTests/Fixtures/" + name
    return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

final class FountainEditorAlignmentTests: XCTestCase {

    func testAlignment_extendedDefaults() {
        let text = """
        Title: X

        INT. ROOM — DAY
        Text
        ## Scene B
        EXT. FIELD — NIGHT
        """
        // Mini (extended)
        let mini = FountainEditorMiniCore.parseStructure(text: text, options: .extended)
        // Teatro defaults already extended
        let rules = RuleSet() // default supports INT./EXT./INT/EXT/I/E
        let full = structureFromTeatro(text: text, rules: rules)
        XCTAssertEqual(mini.acts.count, full.acts.count)
        XCTAssertEqual(mini.acts[0].scenes.count, full.acts[0].count)
    }

    func testAlignment_strictVsExtended() {
        let text = """
        1. INT. GARAGE - DAY
        Text
        I/E. PORCH - NIGHT
        ## Scene C
        TEXT
        """
        // Mini strict: reject numbered + I/E
        let miniStrict = FountainEditorMiniCore.parseStructure(text: text, options: .strict)
        // Teatro strict: only INT./EXT.
        var rulesStrict = RuleSet()
        rulesStrict.sceneHeadingKeywords = ["INT.", "EXT."]
        let fullStrict = structureFromTeatro(text: text, rules: rulesStrict)
        XCTAssertEqual(miniStrict.acts[0].scenes.count, fullStrict.acts[0].count)

        // Mini extended
        let miniExt = FountainEditorMiniCore.parseStructure(text: text, options: .extended)
        // Teatro extended: default
        let fullExt = structureFromTeatro(text: text, rules: RuleSet())
        XCTAssertEqual(miniExt.acts[0].scenes.count, fullExt.acts[0].count)
    }
}

final class FountainEditorFixtureMatrixTests: XCTestCase {
    private func anchorsMini(_ text: String, extended: Bool) -> [String] {
        let s = FountainEditorMiniCore.parseStructure(text: text, options: extended ? .extended : .strict)
        return s.acts.flatMap { act in act.scenes.map { $0.anchor } }
    }
    private func anchorsTeatro(_ text: String, rules: RuleSet) -> [String] {
        let parsed = structureFromTeatro(text: text, rules: rules)
        return parsed.acts.flatMap { $0 }
    }

    func testExtendedFixture_alignment() {
        let text = fixture("extended1.fountain")
        let mini = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        XCTAssertEqual(mini, full)
    }

    func testMixedSectionsGatesSlug_detection() {
        let text = fixture("mixed_sections_slugs.fountain")
        let mini = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        // Only the two section scenes should appear
        XCTAssertEqual(mini.count, 2)
        XCTAssertEqual(full.count, 2)
    }

    func testTransitionsDialogue_noScenes() {
        let text = fixture("transitions_dialogue.fountain")
        let miniExt = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        XCTAssertEqual(miniExt.count, 0)
        XCTAssertEqual(full.count, 0)
    }

    func testCaseSpacingHyphen_alignment() {
        let text = fixture("case_spacing_hyphen.fountain")
        let mini = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        XCTAssertEqual(mini, full)
    }

    func testSimpleSections_alignment() {
        let text = fixture("simple_sections.fountain")
        let mini = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        XCTAssertEqual(mini, full)
    }

    func testStrictRejectsExtendedForms_alignment() {
        let text = fixture("extended1.fountain")
        // strict mini rejects numbered + I/E
        let mini = anchorsMini(text, extended: false)
        var rules = RuleSet()
        rules.sceneHeadingKeywords = ["INT.", "EXT."]
        let full = anchorsTeatro(text, rules: rules)
        XCTAssertEqual(mini, full)
    }

    func testDualDialogueLyricsCentered_noScenes() {
        let text = fixture("dual_dialogue_lyrics_centered.fountain")
        let mini = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        XCTAssertEqual(mini.count, 0)
        XCTAssertEqual(full.count, 0)
    }

    func testSynopsesBoneyardNotes_noScenes() {
        let text = fixture("synopses_boneyard_notes.fountain")
        let mini = anchorsMini(text, extended: true)
        let full = anchorsTeatro(text, rules: RuleSet())
        XCTAssertEqual(mini.count, 0)
        XCTAssertEqual(full.count, 0)
    }
}
