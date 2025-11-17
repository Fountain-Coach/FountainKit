import XCTest
import AppKit
import SwiftUI
@testable import quietframe_sonify_app

@MainActor
final class QuietFrameEditorNumericTests: XCTestCase {
    func testSidebarAndPageMetrics() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let out = tmp.appendingPathComponent("geom.json")
        setenv("QF_EDITOR_GEOMETRY_DUMP", out.path, 1)
        let hosting = NSHostingView(rootView: FountainEditorSurface(frameSize: CGSize(width: 1024, height: 1536)))
        hosting.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let data = try? Data(contentsOf: out),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("geometry dump missing")
            return
        }
        let sidebar = (obj["sidebarWidth"] as? Double) ?? 0
        let pageW = (obj["pageWidth"] as? Double) ?? 0
        let pageH = (obj["pageHeight"] as? Double) ?? 0
        XCTAssertGreaterThanOrEqual(Int(sidebar.rounded()), 220)
        XCTAssertEqual(Int(pageW.rounded()), 1024)
        XCTAssertEqual(Int(pageH.rounded()), 1536)
    }
}
