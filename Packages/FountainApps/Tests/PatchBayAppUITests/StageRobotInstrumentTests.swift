import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class StageRobotInstrumentTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        setenv("PATCHBAY_MIDI_TRANSPORT", "loopback", 1)
        MetalInstrument.setTransportOverride(LoopbackMetalInstrumentTransport.shared)
    }

    override func tearDownWithError() throws {
        MetalInstrument.setTransportOverride(nil)
        LoopbackMetalInstrumentTransport.shared.reset()
        try super.tearDownWithError()
    }

    func testStagePEBaselineAndPage() throws {
        let vm = EditorVM()
        let state = AppState()
        // Add a Stage node and register dashboard props before mounting view
        let id = "stageRobot1"
        vm.nodes.append(PBNode(id: id, title: "Stage Robot", x: 0, y: 0, w: 595, h: 842, ports: []))
        state.registerDashNode(id: id, kind: .stageA4, props: ["title": "Stage Robot", "page": "A4", "margins": "18,18,18,18", "baseline": "12"])

        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        // Allow binder to create instruments
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "PatchBay Canvas", timeout: 3.0) != nil else {
            XCTFail("Canvas transport not ready")
            return
        }
        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "Stage #\(id)", timeout: 3.0) != nil else {
            XCTFail("Stage instrument not found for \(id)")
            return
        }
        guard let bot = MIDIRobot(destName: "Stage #\(id)") else {
            XCTFail("Unable to create robot for \(id)")
            return
        }

        // Change baseline and page via PE SET
        bot.setProperties(["stage.baseline": 14.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        bot.setProperties(["stage.page": 1.0]) // Letter
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        // Assert dashboard reflects changes
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline && state.dashboard[id]?.props["baseline"] != "14.000" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        while Date() < deadline && state.dashboard[id]?.props["page"] != "Letter" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let dash = state.dashboard[id]
        XCTAssertEqual(dash?.props["baseline"], "14.000")
        XCTAssertEqual(dash?.props["page"], "Letter")
    }
}
