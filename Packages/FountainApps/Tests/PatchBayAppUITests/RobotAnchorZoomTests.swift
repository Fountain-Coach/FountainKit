import XCTest
@testable import patchbay_app
import SwiftUI

final class RobotAnchorZoomTests: XCTestCase {
    func testAnchorZoomAroundCenterViaVendorJSON() throws {
        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        // Reset
        robot.setProperties(["zoom": 1.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        var before: (z: Double, tx: Double, ty: Double) = (1.0, 0.0, 0.0)
        var after: (z: Double, tx: Double, ty: Double) = (1.0, 0.0, 0.0)
        let anchor = CGPoint(x: 512, y: 384)
        let exp = expectation(description: "got zoomAround change")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            let op = (u["op"] as? String) ?? ""
            if op == "zoomAround" {
                before = ((u["prev.zoom"] as? Double) ?? 1.0, (u["prev.tx"] as? Double) ?? 0.0, (u["prev.ty"] as? Double) ?? 0.0)
                after = ((u["zoom"] as? Double) ?? 1.0, (u["tx"] as? Double) ?? 0.0, (u["ty"] as? Double) ?? 0.0)
                exp.fulfill()
            }
        }
        robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": Double(anchor.x), "anchor.view.y": Double(anchor.y), "magnification": 0.25])
        wait(for: [exp], timeout: 2.0)
        NotificationCenter.default.removeObserver(obs)
        // Anchor invariance check using Canvas2D math derived from notifications
        var c = Canvas2D(zoom: CGFloat(before.z), translation: CGPoint(x: before.tx, y: before.ty))
        let docPoint = c.viewToDoc(anchor)
        c = Canvas2D(zoom: CGFloat(after.z), translation: CGPoint(x: after.tx, y: after.ty))
        let newView = c.docToView(docPoint)
        XCTAssertLessThan(abs(newView.x - anchor.x), 1.0)
        XCTAssertLessThan(abs(newView.y - anchor.y), 1.0)
    }
}

