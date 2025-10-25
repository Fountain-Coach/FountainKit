import SwiftUI
import AppKit

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = self.documentView else { return rect }
        let docSize = doc.bounds.size
        // Center when document is smaller than clip bounds
        rect.origin.x = max(0, min(rect.origin.x, docSize.width - rect.size.width))
        rect.origin.y = max(0, min(rect.origin.y, docSize.height - rect.size.height))
        return rect
    }
}

struct ZoomScrollView<Content: View>: NSViewRepresentable {
    var contentSize: CGSize
    var fitToVisible: Bool
    var minZoom: CGFloat = 0.25
    var maxZoom: CGFloat = 4.0
    @Binding var zoom: CGFloat
    @ViewBuilder var content: () -> Content

    class Coordinator: NSObject { var parent: ZoomScrollView; weak var scrollView: NSScrollView?; init(_ parent: ZoomScrollView) { self.parent = parent } }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.allowsMagnification = true
        scroll.minMagnification = minZoom
        scroll.maxMagnification = maxZoom
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        let host = NSHostingView(rootView: AnyView(content().frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)))
        host.frame = NSRect(origin: .zero, size: contentSize)
        scroll.documentView = host
        context.coordinator.scrollView = scroll
        // Initial fit
        DispatchQueue.main.async { updateMagnification(scroll, fit: fitToVisible) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let host = scroll.documentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(content().frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading))
            host.frame.size = contentSize
        }
        scroll.minMagnification = minZoom
        scroll.maxMagnification = maxZoom
        updateMagnification(scroll, fit: fitToVisible)
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
