import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class KeyInputContainerKeysTests: XCTestCase {
    func testHostViewOnlyHandlesArrowKeys() {
        let host = KeyInputContainer<EmptyView>.HostView()
        var received: [UInt16] = []
        host.onKey = { (ev: NSEvent) in received.append(ev.keyCode) }

        // Synthesize key events: letter 'A' (keyCode 0) should NOT trigger onKey
        if let a = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0) {
            host.keyDown(with: a)
        }
        // Arrow Left (123) SHOULD trigger onKey
        if let left = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", isARepeat: false, keyCode: 123) {
            host.keyDown(with: left)
        }
        // Arrow Up (126) SHOULD trigger onKey
        if let up = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}", isARepeat: false, keyCode: 126) {
            host.keyDown(with: up)
        }

        XCTAssertEqual(received, [123, 126], "Only arrow key keyCodes should be captured")
    }
}
