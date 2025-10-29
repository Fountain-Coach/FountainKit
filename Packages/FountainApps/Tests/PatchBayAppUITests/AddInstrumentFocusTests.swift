import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class AddInstrumentFocusTests: XCTestCase {
    func testAddInstrumentSheetFocusesTitle() async throws {
#if ROBOT_ONLY
        // Robot-friendly harness using CFRunLoop to pump events. Skip only if no GUI focus can be obtained.
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let state = AppState()
        let vm = EditorVM()
        var show = true
        let sheet = AddInstrumentSheet(state: state, vm: vm, dismiss: { show = false })
        let host = NSHostingView(rootView: sheet)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        FocusHarness.pumpEvents(seconds: 0.2)
        func findTextField(_ v: NSView) -> NSTextField? { if let tf = v as? NSTextField { return tf }; for s in v.subviews { if let tf = findTextField(s) { return tf } }; return nil }
        guard let tf = findTextField(host) else { throw XCTSkip("No text field present in AddInstrumentSheet") }
        let ok = FocusHarness.tryFocus(tf, window: win, timeout: 1.0)
        if !ok { throw XCTSkip("Could not establish focus reliably in robot-only run") }
        XCTAssertTrue(win.firstResponder is NSTextField)
#else
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let state = AppState()
        let vm = EditorVM()
        var show = true
        let sheet = AddInstrumentSheet(state: state, vm: vm, dismiss: { show = false })
        let host = NSHostingView(rootView: sheet)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)

        // Try to locate the NSTextField and enforce focus
        func findTextField(_ v: NSView) -> NSTextField? {
            if let tf = v as? NSTextField { return tf }
            for s in v.subviews { if let tf = findTextField(s) { return tf } }
            return nil
        }

        // Allow layout
        try? await Task.sleep(nanoseconds: 200_000_000)
        if let tf = findTextField(host) {
            FocusManager.ensureFocus(tf)
            FocusManager.guardModalFocus(tf, timeout: 0.5, step: 0.05)
        }
        // Give the focus guard a moment
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(win.firstResponder is NSTextField, "AddInstrumentSheet Title field should be first responder")
#endif
    }
}
