import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class TrackpadBehaviorRobotTests: XCTestCase {
    // Contract: follow‑finger pan — translation increases by viewDelta/zoom on both axes
    func testPanViewDeltaAtZoom1() throws {
        let (win, host, _, _) = makeHost()
        // Wait for renderer ready to avoid race
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        // reset
        wait(for: [readyExp], timeout: 2.0)
        robot.setProperties(["zoom": 1.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        var last: (tx: Double, ty: Double, z: Double) = (0,0,1)
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            let tx = (u["tx"] as? Double)
            let ty = (u["ty"] as? Double)
            let z = (u["zoom"] as? Double)
            MainActor.assumeIsolated {
                last = (tx ?? last.tx, ty ?? last.ty, z ?? last.z)
            }
        }
        // pan by +120 (x), +80 (y) in view points
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.view": 120.0, "dy.view": 80.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertEqual(last.z, 1.0, accuracy: 0.001)
        XCTAssertEqual(last.tx, 120.0, accuracy: 1.0)
        XCTAssertEqual(last.ty, 80.0, accuracy: 1.0)
        NotificationCenter.default.removeObserver(readyObs)
        _ = host; _ = win
    }

    func testPanViewDeltaRespectsZoom() throws {
        let (win2, host, _, _) = makeHost()
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        wait(for: [readyExp], timeout: 2.0)
        robot.setProperties(["zoom": 2.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        var last: (tx: Double, ty: Double, z: Double) = (0,0,2)
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            let tx = (u["tx"] as? Double)
            let ty = (u["ty"] as? Double)
            let z = (u["zoom"] as? Double)
            MainActor.assumeIsolated {
                last = (tx ?? last.tx, ty ?? last.ty, z ?? last.z)
            }
        }
        // At 2x: 120pt view pan → +60 doc; -60pt → -30 doc
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.view": 120.0, "dy.view": -60.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertEqual(last.z, 2.0, accuracy: 0.001)
        XCTAssertEqual(last.tx, 60.0, accuracy: 1.0)
        XCTAssertEqual(last.ty, -30.0, accuracy: 1.0)
        NotificationCenter.default.removeObserver(readyObs)
        _ = host; _ = win2
    }

    func testPinchAnchorStable() throws {
        let (win3, host, _, _) = makeHost()
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        wait(for: [readyExp], timeout: 2.0)
        robot.setProperties(["zoom": 1.0, "translation.x": 0.0, "translation.y": 0.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let anchor = CGPoint(x: 512, y: 384)
        var before: (z: Double, tx: Double, ty: Double) = (1,0,0)
        var after: (z: Double, tx: Double, ty: Double) = (1,0,0)
        let exp = expectation(description: "zoom")
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
        robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": Double(anchor.x), "anchor.view.y": Double(anchor.y), "magnification": 0.2])
        wait(for: [exp], timeout: 2.0)
        NotificationCenter.default.removeObserver(obs)
        var c = Canvas2D(zoom: CGFloat(before.z), translation: CGPoint(x: before.tx, y: before.ty))
        let doc = c.viewToDoc(anchor)
        c = Canvas2D(zoom: CGFloat(after.z), translation: CGPoint(x: after.tx, y: after.ty))
        let newView = c.docToView(doc)
        XCTAssertLessThan(abs(newView.x - anchor.x), 1.0)
        XCTAssertLessThan(abs(newView.y - anchor.y), 1.0)
        NotificationCenter.default.removeObserver(readyObs)
        _ = host; _ = win3
    }

    // Helpers
    private func makeHost() -> (NSWindow, NSHostingView<AnyView>, EditorVM, AppState) {
        let vm = EditorVM(); let state = AppState()
        let content = AnyView(MetalCanvasHost().environmentObject(vm).environmentObject(state))
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        host.layoutSubtreeIfNeeded()
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        return (win, host, vm, state)
    }
}
