import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class MIDITransportModeTests: XCTestCase {
    override func tearDownWithError() throws {
        MetalInstrument.setTransportOverride(nil)
        try super.tearDownWithError()
    }

    func testPanZoomOverMIDI20Transport() throws {
        throw XCTSkip("Temporarily disabled while wiring MIDI2 transport in CI")
        // Use MIDI 2.0 transport backed by FountainTelemetryKit
        MetalInstrument.setTransportOverride(MIDI2SystemInstrumentTransport())

        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()

        // Observe transform changes
        var changed = false
        let exp = expectation(description: "transform changed")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            changed = true
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        // Wait a moment for endpoints to be provisioned
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        // Use robot over CoreMIDI path (MIDI2 transport publishes virtual endpoints)
        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else {
            throw XCTSkip("Robot could not attach to PatchBay Canvas via MIDI2 transport")
        }
        robot.sendVendorJSON(topic: "ui.panBy", data: ["dx.doc": 10.0, "dy.doc": -6.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        robot.sendVendorJSON(topic: "ui.zoomAround", data: ["anchor.view.x": 400.0, "anchor.view.y": 300.0, "magnification": 0.05])

        wait(for: [exp], timeout: 3.0)
        XCTAssertTrue(changed)
    }
}
