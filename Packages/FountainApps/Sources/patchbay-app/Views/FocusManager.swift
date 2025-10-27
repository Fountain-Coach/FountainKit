import AppKit

@MainActor
enum FocusManager {
    /// Best-effort, quick focus: activate app, make the window key, and set first responder.
    static func ensureFocus(_ view: NSView, retries: Int = 5) {
        guard let window = view.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { ensureFocus(view, retries: max(0, retries - 1)) }
            return
        }
        // Stronger activation than NSApp.activate
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        if window.makeFirstResponder(view) { return }
        guard retries > 0 else { return }
        let delay = 0.03 * pow(2.0, Double(5 - retries))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            _ = window.makeFirstResponder(view)
            if window.firstResponder !== view { ensureFocus(view, retries: retries - 1) }
        }
    }

    /// Modal-safe focus guard: for up to `timeout` seconds, keep the app active and
    /// the given view as first responder. This eliminates SwiftUI sheet timing races.
    static func guardModalFocus(_ view: NSView, timeout: TimeInterval = 1.0, step: TimeInterval = 0.08) {
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            guard let window = view.window else {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + step) { tick() }
                }
                return
            }
            if !NSApp.isActive { NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps]) }
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            if window.firstResponder !== view { _ = window.makeFirstResponder(view) }
            if Date() < deadline {
                // Exit early when stable
                if NSApp.isActive, window.isKeyWindow, window.firstResponder === view { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + step) { tick() }
            }
        }
        tick()
    }

    /// Debug helper to print current focus state.
    static func dumpFocus(label: String = "focus") {
        let active = NSApp.isActive
        let keyWin = NSApp.keyWindow
        let keyTitle = keyWin?.title ?? "<none>"
        let responder = String(describing: type(of: keyWin?.firstResponder as Any))
        let modal = NSApp.modalWindow != nil
        let attached = keyWin?.attachedSheet != nil
        fputs("[\(label)] active=\(active) keyWindow=\(keyTitle) responder=\(responder) modal=\(modal) attachedSheet=\(attached)\n", stderr)
    }
}
