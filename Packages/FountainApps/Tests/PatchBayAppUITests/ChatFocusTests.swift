import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class ChatFocusTests: XCTestCase {
    func testChatComposerGetsFirstResponder() async throws {
        let ctrl = ChatSessionController()
        let view = ChatInstrumentView(controller: ctrl, title: "Chat Test")
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)

        // Allow focus/activation retries to settle
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertTrue(win.firstResponder is NSTextView, "ChatInstrumentView composer should hold first responder (NSTextView)")
    }
}

