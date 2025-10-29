import XCTest
@testable import patchbay_app
import SwiftUI

@MainActor
final class TrackpadBehaviorRobotTests: XCTestCase {
    // Contract: follow‑finger pan — translation increases by viewDelta/zoom on both axes
    func testPanViewDeltaAtZoom1() throws {
        let (host, _, _) = makeHost()
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        // reset
        robot.setProperties(["zoom": 1.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        var last: (tx: Double, ty: Double, z: Double) = (0,0,1)
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            last = ((u["tx"] as? Double) ?? last.tx, (u["ty"] as? Double) ?? last.ty, (u["zoom"] as? Double) ?? last.z)
        }
        // pan by +120 (x), +80 (y) in view points
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.view": 120.0, "dy.view": 80.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertEqual(last.z, 1.0, accuracy: 0.001)
        XCTAssertEqual(last.tx, 120.0, accuracy: 1.0)
        XCTAssertEqual(last.ty, 80.0, accuracy: 1.0)
        _ = host
    }

    func testPanViewDeltaRespectsZoom() throws {
        let (host, _, _) = makeHost()
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        robot.setProperties(["zoom": 2.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        var last: (tx: Double, ty: Double, z: Double) = (0,0,2)
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            last = ((u["tx"] as? Double) ?? last.tx, (u["ty"] as? Double) ?? last.ty, (u["zoom"] as? Double) ?? last.z)
        }
        // At 2x: 120pt view pan → +60 doc; -60pt → -30 doc
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.view": 120.0, "dy.view": -60.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertEqual(last.z, 2.0, accuracy: 0.001)
        XCTAssertEqual(last.tx, 60.0, accuracy: 1.0)
        XCTAssertEqual(last.ty, -30.0, accuracy: 1.0)
        _ = host
    }

    func testPinchAnchorStable() throws {
        let (host, _, _) = makeHost()
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        robot.setProperties(["zoom": 1.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let anchor = CGPoint(x: 512, y: 384)
        var before: (z: Double, tx: Double, ty: Double) = (1,0,0)
        var after: (z: Double, tx: Double, ty: Double) = (1,0,0)
        let exp = expectation(description: "zoom")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            if (u["op"] as? String) == "zoomAround" {
                before = ((u["prev.zoom"] as? Double) ?? 1.0, (u["prev.tx"] as? Double) ?? 0.0, (u["prev.ty"] as? Double) ?? 0.0)
                after = ((u["zoom"] as? Double) ?? 1.0, (u["tx"] as? Double) ?? 0.0, (u["ty"] as? Double) ?? 0.0)
                exp.fulfill()
            }
        }
        robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": Double(anchor.x), "anchor.view.y": Double(anchor.y), "magnification": 0.2])
        wait(for: [exp], timeout: 2.0)
        NotificationCenter.default.removeObserver(obs)
        var c = Canvas2D(zoom: CGFloat(before.z), translation: CGPoint(x: before.tx, y: before.ty))
        let doc = c.viewToDoc(anchor)
        c = Canvas2D(zoom: CGFloat(after.z), translation: CGPoint(x: after.tx, y: after.ty))
        let newView = c.docToView(doc)
        XCTAssertLessThan(abs(newView.x - anchor.x), 1.0)
        XCTAssertLessThan(abs(newView.y - anchor.y), 1.0)
        _ = host
    }

    // Helpers
    private func makeHost() -> (NSHostingView<MetalCanvasHost>, EditorVM, AppState) {
        let vm = EditorVM(); let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        host.layoutSubtreeIfNeeded()
        return (host, vm, state)
    }
}
