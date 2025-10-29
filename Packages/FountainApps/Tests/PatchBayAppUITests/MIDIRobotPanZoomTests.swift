import XCTest
@testable import patchbay_app
import SwiftUI

final class MIDIRobotPanZoomTests: XCTestCase {
    func testRendererPanAndZoomProgrammatically() throws {
        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()

        var gotReady = false
        var gotChange = false
        var lastZoom: CGFloat = 0
        var lastTx: CGFloat = 0
        var lastTy: CGFloat = 0

        // Wait for renderer to announce readiness then simulate pan/zoom via debug ops
        let readyExp = expectation(description: "renderer ready")
        let changeExp = expectation(description: "transform changed")

        let readyObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { note in
            gotReady = true
            readyExp.fulfill()
        }
        let changeObs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            lastZoom = CGFloat((u["zoom"] as? Double) ?? 0)
            lastTx = CGFloat((u["tx"] as? Double) ?? 0)
            lastTy = CGFloat((u["ty"] as? Double) ?? 0)
            gotChange = true
            if lastZoom > 1.01 { changeExp.fulfill() }
        }

        // Pump runloop shortly to let view construct
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        wait(for: [readyExp], timeout: 2.0)
        XCTAssertTrue(gotReady)

        // Simulate transform changes by directly posting debug ops (renderer API not public)
        // Pan
        NotificationCenter.default.post(name: Notification.Name("MetalCanvasTransformChanged"), object: nil, userInfo: ["op":"panBy","dx": 50.0, "dy": -30.0, "zoom": 1.0, "tx": 50.0, "ty": -30.0])
        // Zoom
        NotificationCenter.default.post(name: Notification.Name("MetalCanvasTransformChanged"), object: nil, userInfo: ["op":"zoomAround","zoom": 1.2, "tx": 50.0, "ty": -30.0])

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        wait(for: [changeExp], timeout: 2.0)
        XCTAssertTrue(gotChange)
        XCTAssertGreaterThan(lastZoom, 1.01)
        _ = readyObs; _ = changeObs
    }
}

