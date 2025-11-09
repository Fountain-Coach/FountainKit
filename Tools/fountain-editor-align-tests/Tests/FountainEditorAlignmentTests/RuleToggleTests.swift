import XCTest
import FountainEditorCoreKit
import FountainEditorMiniCore
import Teatro

final class FountainEditorRuleToggleTests: XCTestCase {
    private func fixture(_ name: String) -> String {
        let path = "Tools/fountain-editor-align-tests/Tests/FountainEditorAlignmentTests/Fixtures/" + name
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    func testRuleToggles_parityStrictExtended() {
        let text = fixture("extended1.fountain")
        let miniStrict = FountainEditorMiniCore.parseStructure(text: text, options: .strict)
        var strict = RuleSet()
        strict.sceneHeadingKeywords = ["INT.", "EXT."]
        let nodes = FountainParser(rules: strict).parse(text)
        let countStrict = nodes.filter { if case .sceneHeading = $0.type { true } else { false } }.count
        XCTAssertEqual(miniStrict.acts[0].scenes.count, countStrict)

        let miniExt = FountainEditorMiniCore.parseStructure(text: text, options: .extended)
        let nodesExt = FountainParser(rules: RuleSet()).parse(text)
        let countExt = nodesExt.filter { if case .sceneHeading = $0.type { true } else { false } }.count
        XCTAssertEqual(miniExt.acts[0].scenes.count, countExt)
    }
}

