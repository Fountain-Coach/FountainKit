import AppKit
import CoreFoundation

enum FocusHarness {
    @discardableResult
    static func pumpEvents(seconds: TimeInterval, step: TimeInterval = 0.02) -> Int {
        var ticks = 0
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, step, false)
            ticks += 1
        }
        return ticks
    }

    @MainActor
    static func tryFocus(_ view: NSView, window: NSWindow, timeout: TimeInterval = 1.0) -> Bool {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        window.makeKeyAndOrderFront(nil)
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            _ = window.makeFirstResponder(view)
            if window.firstResponder === view { return true }
            pumpEvents(seconds: 0.05)
        }
        return window.firstResponder === view
    }
}
