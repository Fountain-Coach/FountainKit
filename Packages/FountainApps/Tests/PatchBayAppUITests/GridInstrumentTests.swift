import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class GridInstrumentTests: XCTestCase {
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
    func testGridPEUpdatesVM() throws {
        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "Grid", timeout: 2.0) != nil else {
            throw XCTSkip("Grid instrument not present")
        }
        guard let gridBot = MIDIRobot(destName: "Grid") else { throw XCTSkip("No robot for Grid") }

        gridBot.setProperties(["grid.minor": 18.0, "grid.majorEvery": 3.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(vm.grid, 18)
        XCTAssertEqual(vm.majorEvery, 3)
    }
}

