import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
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
            if (u["op"] as? String) == "zoomAround" {
                let pz = (u["prev.zoom"] as? Double) ?? 1.0
                let ptx = (u["prev.tx"] as? Double) ?? 0.0
                let pty = (u["prev.ty"] as? Double) ?? 0.0
                let nz = (u["zoom"] as? Double) ?? 1.0
                let ntx = (u["tx"] as? Double) ?? 0.0
                let nty = (u["ty"] as? Double) ?? 0.0
                MainActor.assumeIsolated {
                    before = (pz, ptx, pty)
                    after = (nz, ntx, nty)
                    exp.fulfill()
                }
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

    func testAnchorZoomSweeps() throws {
        let vm = EditorVM(); let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 768); host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        robot.setProperties(["zoom": 1.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let anchors = [CGPoint(x: 128, y: 96), CGPoint(x: 512, y: 384), CGPoint(x: 900, y: 700)]
        for a in anchors {
            var before: (z: Double, tx: Double, ty: Double) = (1.0,0,0)
            var after: (z: Double, tx: Double, ty: Double) = (1.0,0,0)
            let exp = expectation(description: "zoom change \(a)")
            let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
                let u = note.userInfo ?? [:]
                if (u["op"] as? String) == "zoomAround" {
                    let pz = (u["prev.zoom"] as? Double) ?? 1.0
                    let ptx = (u["prev.tx"] as? Double) ?? 0.0
                    let pty = (u["prev.ty"] as? Double) ?? 0.0
                    let nz = (u["zoom"] as? Double) ?? 1.0
                    let ntx = (u["tx"] as? Double) ?? 0.0
                    let nty = (u["ty"] as? Double) ?? 0.0
                    MainActor.assumeIsolated {
                        before = (pz, ptx, pty)
                        after = (nz, ntx, nty)
                        exp.fulfill()
                    }
                }
            }
            robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": Double(a.x), "anchor.view.y": Double(a.y), "magnification": 0.2])
            wait(for: [exp], timeout: 2.0)
            NotificationCenter.default.removeObserver(obs)
            var c = Canvas2D(zoom: CGFloat(before.z), translation: CGPoint(x: before.tx, y: before.ty))
            let docPoint = c.viewToDoc(a)
            c = Canvas2D(zoom: CGFloat(after.z), translation: CGPoint(x: after.tx, y: after.ty))
            let newView = c.docToView(docPoint)
            XCTAssertLessThan(abs(newView.x - a.x), 1.0)
            XCTAssertLessThan(abs(newView.y - a.y), 1.0)
        }
    }
}
