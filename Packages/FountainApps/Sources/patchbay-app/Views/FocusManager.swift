import AppKit

@MainActor
enum FocusManager {
    static func ensureFocus(_ view: NSView, retries: Int = 5) {
        guard let window = view.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { ensureFocus(view, retries: max(0, retries - 1)) }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if window.makeFirstResponder(view) { return }
        guard retries > 0 else { return }
        let delay = 0.03 * pow(2.0, Double(5 - retries))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            _ = window.makeFirstResponder(view)
            if window.firstResponder !== view { ensureFocus(view, retries: retries - 1) }
        }
    }
}
