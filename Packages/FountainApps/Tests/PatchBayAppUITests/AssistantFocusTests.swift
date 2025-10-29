import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class AssistantFocusTests: XCTestCase {
    func testAssistantTextEditorGetsFocusOnAppear() async throws {
        throw XCTSkip("AssistantPane not present in current UI")
        /*
        let state = AppState()
        let vm = EditorVM()
        let view = AssistantPane().environmentObject(state).environmentObject(vm)
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)

        // Allow onAppear + focus to settle
        try? await Task.sleep(nanoseconds: 300_000_000)

        // NSTextView is the native editor backing TextEditor; assert it is firstResponder
        XCTAssertTrue(win.firstResponder is NSTextView, "Assistant TextEditor should hold first responder by default")
        */
    }
}
