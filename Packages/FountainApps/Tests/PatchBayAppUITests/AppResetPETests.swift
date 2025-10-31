import XCTest
@testable import patchbay_app
import SwiftUI
import AppKit

@MainActor
final class AppResetPETests: XCTestCase {
    func testAppPECanvasResetResetsCanvasTransform() throws {
        let vm = EditorVM(); let state = AppState()
        // Build a minimal stack with App instrument + Canvas
        let root = AnyView(HStack(spacing: 0) {
            PatchBayAppInstrumentBinder().environmentObject(state)
            MetalCanvasHost().environmentObject(vm).environmentObject(state)
        })
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        defer { win.orderOut(nil) }

        // Wait for renderer ready
        var gotReady = false
        let readyExp = expectation(description: "renderer ready")
        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { _ in
            if !gotReady { gotReady = true; readyExp.fulfill() }
        }
        wait(for: [readyExp], timeout: 2.0)
        NotificationCenter.default.removeObserver(readyObs)

        // Move away from defaults via Canvas PE to make reset meaningful
        guard let canvasBot = MIDIRobot(destName: "PatchBay Canvas") else { throw XCTSkip("Canvas dest not found") }
        canvasBot.setProperties(["zoom": 1.5, "translation.x": 20.0, "translation.y": -12.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // Trigger App-level PE reset
        guard let appBot = MIDIRobot(destName: "PatchBay App") else { throw XCTSkip("App dest not found") }
        let exp = expectation(description: "transform set")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            if (note.userInfo?["op"] as? String) == "set" { exp.fulfill() }
        }
        appBot.setProperties(["canvas.reset": 1.0])
        wait(for: [exp], timeout: 1.5)
        NotificationCenter.default.removeObserver(obs)

        XCTAssertEqual(vm.zoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(vm.translation.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(vm.translation.y, 0.0, accuracy: 0.001)
    }
}
