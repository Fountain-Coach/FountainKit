import XCTest
import AppKit
import SwiftUI
@testable import quietframe_editor_app

@MainActor
final class EditorNumericTests: XCTestCase {
    func testNumericInvariants_outlineAndGutter() throws {
        // Skip in headless runs unless explicitly enabled
        if ProcessInfo.processInfo.environment["EDITOR_NUMERIC_ENABLE"] != "1" {
            throw XCTSkip("Numeric invariants disabled in headless runs")
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let out = tmp.appendingPathComponent("geom.json")
        setenv("EDITOR_SEED_TEXT", "# Act 1\n\n## Scene One\n\nINT. SCENE ONE — DAY\n\nText.", 1)
        setenv("EDITOR_GEOMETRY_DUMP", out.path, 1)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: EditorLandingView())
        hosting.frame = win.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        win.contentView!.addSubview(hosting)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        win.close()

        let data = try Data(contentsOf: out)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let outline = obj?["outlineWidth"] as? Double ?? 0
        let gutter = obj?["gutterWidth"] as? Double ?? 0
        XCTAssertGreaterThanOrEqual(outline, 220, "outline min width")
        XCTAssertEqual(Int(gutter.rounded()), 14, "gutter width")
    }
}
