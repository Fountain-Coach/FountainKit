import AppKit

@MainActor
enum FocusManager {
    /// Best-effort, quick focus: activate app, make the window key, and set first responder.
    static func ensureFocus(_ view: NSView, retries: Int = 5) {
        guard retries >= 0 else { return }
        if let window = view.window {
            // Stronger activation than NSApp.activate
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            if window.makeFirstResponder(view) { return }
            guard retries > 0 else { return }
            let delay = 0.03 * pow(2.0, Double(5 - retries))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if window.firstResponder !== view {
                    ensureFocus(view, retries: retries - 1)
                }
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                ensureFocus(view, retries: max(0, retries - 1))
            }
        }
    }

    /// Modal-safe focus guard: for up to `timeout` seconds, keep the app active and
    /// the given view as first responder. This eliminates SwiftUI sheet timing races.
    static func guardModalFocus(_ view: NSView, timeout: TimeInterval = 1.0, step: TimeInterval = 0.08) {
        let deadline = Date().addingTimeInterval(timeout)
        Task { @MainActor in
            while Date() < deadline {
                guard let window = view.window else {
                    try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                    continue
                }
                if !NSApp.isActive {
                    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
                }
                if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                if window.firstResponder !== view { _ = window.makeFirstResponder(view) }
                // Exit early when stable
                if NSApp.isActive, window.isKeyWindow, window.firstResponder === view { return }
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            }
        }
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
