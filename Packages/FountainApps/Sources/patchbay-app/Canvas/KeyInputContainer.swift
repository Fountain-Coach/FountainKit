import SwiftUI
import AppKit

struct KeyInputContainer<Content: View>: NSViewRepresentable {
    var onKey: (NSEvent) -> Void
    @ViewBuilder var content: () -> Content

    class HostView: NSView {
        var onKey: ((NSEvent) -> Void)?
        weak var host: NSHostingView<AnyView>?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            // Only intercept navigation keys; let typing go to focused controls (e.g., TextEditor)
            let arrows: Set<UInt16> = [123, 124, 125, 126] // left, right, down, up
            if arrows.contains(event.keyCode) {
                onKey?(event)
            } else {
                super.keyDown(with: event)
            }
        }
        override func mouseDown(with event: NSEvent) {
            // Click to focus the canvas, so arrow keys work after a click
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let v = HostView()
        v.onKey = onKey
        let host = NSHostingView(rootView: AnyView(content()))
        v.addSubview(host)
        v.host = host
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            host.topAnchor.constraint(equalTo: v.topAnchor),
            host.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])
        return v
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let hv = (view as? HostView), let host = hv.host {
            host.rootView = AnyView(content())
        }
    }
}
