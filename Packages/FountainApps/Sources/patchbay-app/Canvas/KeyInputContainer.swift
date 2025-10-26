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
            onKey?(event)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                _ = self?.window?.makeFirstResponder(self)
            }
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

