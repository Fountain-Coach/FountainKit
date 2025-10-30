import XCTest
@testable import patchbay_app
import SwiftUI

@MainActor
final class CanvasDefaultTransformTests: XCTestCase {
    func testStartsAtCanonicalDefaults() throws {
        let vm = EditorVM()
        let state = AppState()
        // Pre-set canonical defaults
        vm.translation = .zero
        vm.zoom = 1.0

        var gotReady = false
        var readyRenderer: AnyObject? = nil
        let readyExp = expectation(description: "renderer ready")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { note in
            gotReady = true
            readyRenderer = note.userInfo?["renderer"] as AnyObject?
            readyExp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        defer { win.orderOut(nil) }

        wait(for: [readyExp], timeout: 2.0)
        XCTAssertTrue(gotReady)
        // After ready, the VM should still be at canonical defaults
        XCTAssertEqual(vm.zoom, 1.0, accuracy: 0.0001)
        XCTAssertEqual(vm.translation.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(vm.translation.y, 0.0, accuracy: 0.0001)
        _ = readyRenderer
    }
}

