import XCTest
import AppKit
import SwiftUI
@testable import quietframe_editor_app

@MainActor
final class EditorNumericTests: XCTestCase {
    func testNumericInvariants_outlineAndGutter() throws {
        // Prefer reading geometry dump if available (GUI session), otherwise
        // assert hard invariants derived from the view's constants.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let out = tmp.appendingPathComponent("geom.json")
        setenv("EDITOR_SEED_TEXT", "# Act 1\n\n## Scene One\n\nINT. SCENE ONE — DAY\n\nText.", 1)
        setenv("EDITOR_GEOMETRY_DUMP", out.path, 1)

        let hosting = NSHostingView(rootView: EditorLandingView())
        hosting.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        if let data = try? Data(contentsOf: out),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let outline = obj["outlineWidth"] as? Double,
           let gutter = obj["gutterWidth"] as? Double {
            XCTAssertGreaterThanOrEqual(outline, Double(EditorLandingView.outlineMinWidthPx) - 0.5, "outline min width")
            XCTAssertEqual(Int(gutter.rounded()), Int(EditorLandingView.gutterWidthPx.rounded()), "gutter width")
        } else {
            // Fallback assertions without geometry file (headless)
            XCTAssertEqual(Int(EditorLandingView.gutterWidthPx), 14)
            XCTAssertGreaterThanOrEqual(Int(EditorLandingView.outlineMinWidthPx), 220)
        }
    }
}
