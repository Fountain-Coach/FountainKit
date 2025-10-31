import XCTest
@testable import patchbay_app
import SwiftUI

@MainActor
final class MIDIMonitorEventsTests: XCTestCase {
    func testCanvasResetEmitsZoomAndPanEvents() throws {
        let (win, host, _, _) = makeHost()
        defer { _ = host; _ = win }
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        wait(for: [readyExp], timeout: 2.0)
        NotificationCenter.default.removeObserver(readyObs)
        // Collect monitor events while issuing reset
        var sawZoom = false
        var sawPan = false
        let obs = NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            let t = (note.userInfo?["type"] as? String) ?? ""
            if t == "ui.zoom" || t == "ui.zoom.debug" { sawZoom = true }
            if t == "ui.pan" || t == "ui.pan.debug" { sawPan = true }
        }
        // First, move to a non-default, then reset to ensure changes
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.view": 60.0, "dy.view": -30.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": 320.0, "anchor.view.y": 240.0, "magnification": 0.15])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        robot.sendVendorJSON(topic: "canvas.reset", data: [:])
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertTrue(sawZoom, "expected at least one ui.zoom(.debug) event after reset")
        XCTAssertTrue(sawPan, "expected at least one ui.pan(.debug) event after reset")
    }

    func testZoomAroundEmitsMonitorEvent() throws {
        let (win, host, _, _) = makeHost(); defer { _ = host; _ = win }
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        wait(for: [readyExp], timeout: 2.0)
        NotificationCenter.default.removeObserver(readyObs)
        var sawZoom = false
        let obs = NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            let t = (note.userInfo?["type"] as? String) ?? ""
            if t == "ui.zoom" || t == "ui.zoom.debug" { sawZoom = true }
        }
        robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": 400.0, "anchor.view.y": 300.0, "magnification": 0.2])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertTrue(sawZoom)
    }

    func testPanEmitsMonitorEvent() throws {
        let (win, host, _, _) = makeHost(); defer { _ = host; _ = win }
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        wait(for: [readyExp], timeout: 2.0)
        NotificationCenter.default.removeObserver(readyObs)
        var sawPan = false
        let obs = NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            let t = (note.userInfo?["type"] as? String) ?? ""
            if t == "ui.pan" || t == "ui.pan.debug" { sawPan = true }
        }
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.view": 100.0, "dy.view": -40.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertTrue(sawPan)
    }

    // Helpers: mirror TrackpadBehaviorRobotTests harness
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

