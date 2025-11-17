import SwiftUI
import AppKit
extension Notification.Name {
    static let qcZoomFit = Notification.Name("qcZoomFit")
    static let qcZoomOne = Notification.Name("qcZoomOne")
    static let qcZoomIn = Notification.Name("qcZoomIn")
    static let qcZoomOut = Notification.Name("qcZoomOut")
    static let qcPanHold = Notification.Name("qcPanHold")
    static let qcPanDelta = Notification.Name("qcPanDelta")
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = self.documentView else { return rect }
        let docSize = doc.bounds.size
        // If document smaller than clip, center it; otherwise clamp within bounds
        if docSize.width <= rect.size.width {
            rect.origin.x = (docSize.width - rect.size.width) / 2.0
        } else {
            rect.origin.x = max(0, min(rect.origin.x, docSize.width - rect.size.width))
        }
        if docSize.height <= rect.size.height {
            rect.origin.y = (docSize.height - rect.size.height) / 2.0
        } else {
            rect.origin.y = max(0, min(rect.origin.y, docSize.height - rect.size.height))
        }
        return rect
    }
}

struct ZoomScrollView<Content: View>: NSViewRepresentable {
    var contentSize: CGSize
    var fitRect: CGRect? = nil
    var fitToVisible: Bool
    var minZoom: CGFloat = 0.25
    var maxZoom: CGFloat = 4.0
    @Binding var zoom: CGFloat
    @ViewBuilder var content: () -> Content

    @MainActor
    class Coordinator: NSObject {
        var parent: ZoomScrollView
        weak var scrollView: NSScrollView?
        var observation: NSKeyValueObservation?
        var didFit = false
        var lastSize: CGSize = .zero
        init(_ parent: ZoomScrollView) { self.parent = parent }
        var keyDownMonitor: Any?
        var keyUpMonitor: Any?
        var scrollMonitor: Any?
        @objc func handleMagnify(_ gr: NSMagnificationGestureRecognizer) {
            guard let sv = scrollView else { return }
            switch gr.state {
            case .began:
                break
            case .changed:
                let base = sv.magnification
                // recognizer.magnification is a delta since last callback; apply multiplicatively
                let newMag = max(parent.minZoom, min(parent.maxZoom, base * (1.0 + gr.magnification)))
                let loc = gr.location(in: sv.contentView)
                sv.setMagnification(newMag, centeredAt: loc)
            default:
                break
            }
        }
        @objc func handleDoubleClick(_ gr: NSClickGestureRecognizer) {
            guard let sv = scrollView else { return }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let loc = gr.location(in: sv.contentView)
            if flags.contains(.option) {
                // 100% at click
                sv.setMagnification(1.0, centeredAt: loc)
            } else {
                // Fit to visible
                let vis = sv.contentView.bounds.size
                let docSize = sv.documentView?.bounds.size ?? .zero
                let sx = vis.width / max(1, docSize.width)
                let sy = vis.height / max(1, docSize.height)
                let m = max(parent.minZoom, min(parent.maxZoom, min(sx, sy)))
                sv.setMagnification(m, centeredAt: CGPoint(x: vis.width/2, y: vis.height/2))
                // Center the document after fit
                centerDocument(sv)
            }
        }

        func centerDocument(_ sv: NSScrollView) {
            guard let doc = sv.documentView else { return }
            let docSize = doc.bounds.size
            let clip = sv.contentView.bounds.size
            let ox = max(0, (docSize.width - clip.width) / 2)
            let oy = max(0, (docSize.height - clip.height) / 2)
            sv.contentView.setBoundsOrigin(NSPoint(x: ox, y: oy))
            sv.reflectScrolledClipView(sv.contentView)
        }

        func fit(_ rect: CGRect, in sv: NSScrollView) {
            let clip = sv.contentView.bounds.size
            let sx = clip.width / max(1, rect.width)
            let sy = clip.height / max(1, rect.height)
            let m = max(parent.minZoom, min(parent.maxZoom, min(sx, sy)))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            sv.setMagnification(m, centeredAt: CGPoint(x: clip.width/2, y: clip.height/2))
            let ox = max(0, center.x - clip.width/(2*m))
            let oy = max(0, center.y - clip.height/(2*m))
            sv.contentView.setBoundsOrigin(NSPoint(x: ox, y: oy))
            sv.reflectScrolledClipView(sv.contentView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        // We'll handle pinch ourselves to anchor at finger location
        scroll.allowsMagnification = false
        scroll.minMagnification = minZoom
        scroll.maxMagnification = maxZoom
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        let host = NSHostingView(rootView: AnyView(content().frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)))
        host.frame = NSRect(origin: .zero, size: contentSize)
        scroll.documentView = host
        context.coordinator.scrollView = scroll
        context.coordinator.observation = scroll.observe(\NSScrollView.magnification, options: [.new]) { [weak coord = context.coordinator] sv, _ in
            Task { @MainActor in coord?.parent.zoom = sv.magnification }
        }
        // Add magnification recognizer to anchor zoom under the fingers
        let mag = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
        scroll.contentView.addGestureRecognizer(mag)
        // Double-click to fit (Option-double-click to 100% at click)
        let dbl = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        dbl.numberOfClicksRequired = 2
        scroll.contentView.addGestureRecognizer(dbl)
        // Initial fit (once) and center
        Task { @MainActor in
            if let rect = fitRect {
                context.coordinator.fit(rect, in: scroll)
            } else {
                updateMagnification(scroll, fit: fitToVisible)
            }
            context.coordinator.didFit = fitToVisible
            context.coordinator.lastSize = contentSize
            context.coordinator.centerDocument(scroll)
        }
        // Spacebar temporary pan (post notifications)
        context.coordinator.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 49 { NotificationCenter.default.post(name: .qcPanHold, object: nil, userInfo: ["down": true]); return nil }
            return e
        }
        context.coordinator.keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { e in
            if e.keyCode == 49 { NotificationCenter.default.post(name: .qcPanHold, object: nil, userInfo: ["down": false]); return nil }
            return e
        }
        // Listen for trackpad/scroll pan and post deltas in doc space for service pan
        context.coordinator.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coord = context.coordinator] e in
            guard let sv = coord?.scrollView else { return e }
            // Convert scroll deltas (view space) to doc-space deltas; invert to match visual movement
            let mag = max(0.0001, sv.magnification)
            let dx = -Double(e.scrollingDeltaX) / Double(mag)
            let dy = -Double(e.scrollingDeltaY) / Double(mag)
            if abs(dx) > 0.001 || abs(dy) > 0.001 {
                NotificationCenter.default.post(name: .qcPanDelta, object: nil, userInfo: ["dx": dx, "dy": dy])
            }
            return e
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let host = scroll.documentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(content().frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading))
            host.frame.size = contentSize
        }
        scroll.minMagnification = minZoom
        scroll.maxMagnification = maxZoom
        // Avoid fit loop: only fit when requested (fitToVisible true) and not already fit,
        // or when content size changed.
        if fitToVisible {
            if context.coordinator.didFit == false || context.coordinator.lastSize != contentSize {
                if let rect = fitRect { context.coordinator.fit(rect, in: scroll) }
                else { updateMagnification(scroll, fit: true) }
                context.coordinator.didFit = true
                context.coordinator.lastSize = contentSize
                context.coordinator.centerDocument(scroll)
            }
        } else {
            context.coordinator.didFit = false
        }
    }

    private func updateMagnification(_ scroll: NSScrollView, fit: Bool) {
        guard let clip = scroll.contentView as? NSClipView else { return }
        if fit {
            // Fit to visible area maintaining aspect
            let vis = clip.bounds.size
            let sx = vis.width / max(1, contentSize.width)
            let sy = vis.height / max(1, contentSize.height)
            let m = max(minZoom, min(maxZoom, min(sx, sy)))
            if abs(scroll.magnification - m) > 0.001 { scroll.magnification = m }
        } else {
            let m = max(minZoom, min(maxZoom, zoom))
            if abs(scroll.magnification - m) > 0.001 { scroll.magnification = m }
        }
    }
}
