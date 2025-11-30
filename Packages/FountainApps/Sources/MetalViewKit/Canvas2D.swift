// MetalViewKit — Canonical 2D transform (doc ↔ view)
//
// Canvas2D is the shared camera model for infinite canvases in this workspace.
// It is intentionally UI‑agnostic and depends only on CoreGraphics so it can be
// reused by MetalViewKit, SDLKit-based apps (Infinity), and tests.

#if canImport(CoreGraphics)
import CoreGraphics

public struct Canvas2D {
    public var zoom: CGFloat    // uniform scale (>= minZoom, <= maxZoom)
    public var translation: CGPoint // doc-space translation (pre-scale)
    public var minZoom: CGFloat = 0.25
    public var maxZoom: CGFloat = 3.0
    public static let defaultZoom: CGFloat = 1.0
    public static let defaultTranslation: CGPoint = .zero

    public init(zoom: CGFloat = 1.0, translation: CGPoint = .zero) {
        self.zoom = zoom
        self.translation = translation
    }
    public mutating func clamp() { zoom = max(minZoom, min(maxZoom, zoom)) }

    // Map a doc-space point to a view-space point
    public func docToView(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x + translation.x) * zoom,
                                                            y: (p.y + translation.y) * zoom) }

    // Map a view-space point to doc-space
    public func viewToDoc(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x / max(0.0001, zoom)) - translation.x,
                                                            y: (p.y / max(0.0001, zoom)) - translation.y) }

    // Pan by a view-space delta (follow-finger). Equivalent to applying doc delta = viewDelta / zoom
    public mutating func panBy(viewDelta: CGSize) {
        let s = max(0.0001, zoom)
        translation.x += viewDelta.width / s
        translation.y += viewDelta.height / s
    }

    // Anchor-stable zoom: adjust zoom by magnification around a view-space anchor
    public mutating func zoomAround(viewAnchor a: CGPoint, magnification m: CGFloat) {
        let z0 = max(0.0001, zoom)
        let z1 = max(minZoom, min(maxZoom, z0 * (1.0 + m)))
        // Keep the doc point under the anchor stationary in view space
        // v = (d + T) * Z => T' = T + a * (1/Z' - 1/Z)
        translation.x = translation.x + a.x * (1.0 / z1 - 1.0 / z0)
        translation.y = translation.y + a.y * (1.0 / z1 - 1.0 / z0)
        zoom = z1
    }
}

#endif
