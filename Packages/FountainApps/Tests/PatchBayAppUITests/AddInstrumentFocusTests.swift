import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class AddInstrumentFocusTests: XCTestCase {
    func testAddInstrumentSheetFocusesTitle() async throws {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let state = AppState()
        let vm = EditorVM()
        var show = true
        let sheet = AddInstrumentSheet(state: state, vm: vm, dismiss: { show = false })
        let host = NSHostingView(rootView: sheet)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)

        // Allow focus settling (retry window)
        try? await Task.sleep(nanoseconds: 600_000_000)

        // Expect NSTextField to hold first responder (the custom FocusTextField)
        XCTAssertTrue(win.firstResponder is NSTextField, "AddInstrumentSheet Title field should be first responder")
    }
}
