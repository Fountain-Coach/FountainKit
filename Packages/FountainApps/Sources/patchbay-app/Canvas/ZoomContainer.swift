import SwiftUI
import AppKit
import MetalViewKit

struct ZoomContainer<Content: View>: NSViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var translation: CGPoint
    @ViewBuilder var content: () -> Content

    @MainActor
    class Coordinator: NSObject {
        var parent: ZoomContainer
        weak var host: NSHostingView<AnyView>?
        init(_ parent: ZoomContainer) { self.parent = parent }

        @objc func handleMagnify(_ gr: NSMagnificationGestureRecognizer) {
            guard let host = host else { return }
            switch gr.state {
            case .began: break
            case .changed:
                let base = parent.zoom
                let newScale = max(0.25, min(3.0, base * (1.0 + gr.magnification)))
                let loc = gr.location(in: host)
                // Anchor zoom at pointer location: keep doc point under cursor stable
                let s = max(0.0001, base)
                let docX = CGFloat(loc.x) / s - parent.translation.x
                let docY = CGFloat(loc.y) / s - parent.translation.y
                let s2 = max(0.0001, newScale)
                let newTx = CGFloat(loc.x) / s2 - docX
                let newTy = CGFloat(loc.y) / s2 - docY
                parent.translation = CGPoint(x: newTx, y: newTy)
                parent.zoom = newScale
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "ui.zoom", "zoom": Double(newScale)])
            default: break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        // Defer building content until next runloop to avoid early env-object access during init
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        context.coordinator.host = host
        let view = NSView()
        view.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // Add magnification recognizer
        let mag = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
        view.addGestureRecognizer(mag)
        // Trackpad scroll to pan in doc space
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coord = context.coordinator] e in
            guard let coord, let win = host.window, e.window == win else { return e }
            if NSApp.modalWindow != nil || win.attachedSheet != nil { return e }
            let s = max(0.0001, coord.parent.zoom)
            // Make horizontal follow finger.
            let invX: CGFloat = e.isDirectionInvertedFromDevice ? 1.0 : -1.0
            // Vertical: ensure swipe up moves content up (doc translation decreases).
            let invY: CGFloat = e.isDirectionInvertedFromDevice ? -1.0 : 1.0
            coord.parent.translation.x += invX * (e.scrollingDeltaX / s)
            coord.parent.translation.y += invY * (e.scrollingDeltaY / s)
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "ui.pan", "x": Double(coord.parent.translation.x), "y": Double(coord.parent.translation.y)
            ])
            return e
        }
        // Install content after view is set up
        DispatchQueue.main.async {
            host.rootView = AnyView(content())
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = context.coordinator.host else { return }
        // Defer updating the hosted rootView to avoid re-entrancy during SwiftUI updates
        DispatchQueue.main.async {
            host.rootView = AnyView(content())
        }
    }
}
