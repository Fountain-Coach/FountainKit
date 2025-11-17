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
        // Smooth pan animator
        var panTarget: CGPoint = .zero
        private var panTimer: Timer?
        private let stepInterval: TimeInterval = 1.0/120.0
        private let alpha: CGFloat = 0.28 // smoothing factor per tick
        // Adaptive calibration so doc deltas match raw deltas / zoom.
        var panGainX: CGFloat = 1.0
        var panGainY: CGFloat = 1.0
        let calibrateAlpha: CGFloat = 0.12
        func startPanAnimator() {
            if panTimer == nil {
                panTimer = Timer.scheduledTimer(timeInterval: stepInterval, target: self, selector: #selector(tickPanAnimatorMain), userInfo: nil, repeats: true)
            }
        }
        @objc private func tickPanAnimatorMain() { tickPanAnimator() }
        private func tickPanAnimator() {
            let cur = parent.translation
            let tgt = panTarget
            let dx = tgt.x - cur.x
            let dy = tgt.y - cur.y
            if abs(dx) < 0.01 && abs(dy) < 0.01 { parent.translation = tgt; return }
            parent.translation = CGPoint(x: cur.x + dx * alpha, y: cur.y + dy * alpha)
        }

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
            // Use adaptive gain to align doc deltas with raw deltas / zoom
            let rawX = e.scrollingDeltaX
            let rawY = e.scrollingDeltaY
            var dxDoc = (coord.panGainX * rawX) / s
            var dyDoc = (coord.panGainY * rawY) / s
            // Calibrate sign + magnitude progressively
            func tune(gain: inout CGFloat, raw: CGFloat, doc: CGFloat) {
                guard raw != 0 else { return }
                if doc * raw < 0 { gain = -gain } // fix sign immediately
                let desired = abs(raw) / s
                let actual = max(0.0001, abs(doc))
                let r = desired / actual
                gain = gain * (1 - coord.calibrateAlpha) + gain * r * coord.calibrateAlpha
            }
            tune(gain: &coord.panGainX, raw: rawX, doc: dxDoc)
            tune(gain: &coord.panGainY, raw: rawY, doc: dyDoc)
            // Recompute with tuned gains for the applied step
            dxDoc = (coord.panGainX * rawX) / s
            dyDoc = (coord.panGainY * rawY) / s
            coord.panTarget = CGPoint(x: coord.parent.translation.x + dxDoc,
                                      y: coord.parent.translation.y + dyDoc)
            coord.startPanAnimator()
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "ui.pan",
                "x": Double(coord.panTarget.x),
                "y": Double(coord.panTarget.y),
                "dx.doc": Double(dxDoc),
                "dy.doc": Double(dyDoc),
                "dx.raw": Double(e.scrollingDeltaX),
                "dy.raw": Double(e.scrollingDeltaY),
                "precise": e.hasPreciseScrollingDeltas
            ])
            return e
        }
        // Install content after view is set up
        Task { @MainActor in
            host.rootView = AnyView(content())
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = context.coordinator.host else { return }
        // Defer updating the hosted rootView to avoid re-entrancy during SwiftUI updates
        Task { @MainActor in
            host.rootView = AnyView(content())
        }
    }
}
