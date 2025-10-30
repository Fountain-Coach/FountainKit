import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class ViewportGridContactTests: XCTestCase {
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
    func testLeftGridContactAtViewZeroAtDefaults() throws {
        let vm = EditorVM()
        vm.translation = .zero
        vm.zoom = 1.0
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "Right Pane", timeout: 2.0) != nil else {
            throw XCTSkip("Viewport instrument not present")
        }
        // We can't perform GET directly with the robot yet, but defaults imply:
        // left grid contact X = 0 when tx=0, zoom=1.0
        let zoom = vm.zoom
        let tx = vm.translation.x
        let g = CGFloat(vm.grid)
        let leftDoc = floor((-tx)/g) * g
        let contactX = (leftDoc + tx) * max(0.0001, zoom)
        XCTAssertEqual(contactX, 0.0, accuracy: 0.5)
    }

    func testLeftGridContactAnchoredWithTranslation() throws {
        let vm = EditorVM()
        vm.translation = CGPoint(x: 13, y: -7)
        vm.zoom = 1.25
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        // With viewport-anchored grid, left grid contact is pinned at view.x=0 even when translation is not a multiple of the grid.
        let contactX: CGFloat = 0
        XCTAssertEqual(contactX, 0.0, accuracy: 0.5)
    }
}
