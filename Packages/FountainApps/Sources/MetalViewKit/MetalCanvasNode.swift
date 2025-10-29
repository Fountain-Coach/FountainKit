// MetalViewKit — Metal-backed node protocol for a shared canvas
// Nodes render their body in doc-space, provide port geometry, and handle hit-testing.

#if canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import Foundation
import CoreGraphics
import Metal
import MetalKit

public enum MetalNodePortSide: String, Sendable { case left, right, top, bottom }
public enum MetalNodePortDir: String, Sendable { case input, output }

public struct MetalNodePort: Sendable, Hashable {
    public var id: String
    public var side: MetalNodePortSide
    public var dir: MetalNodePortDir
    /// Port center in node-local coordinates (0,0) == node's top-left in doc-space
    public var centerLocal: CGPoint
    public init(id: String, side: MetalNodePortSide, dir: MetalNodePortDir, centerLocal: CGPoint) {
        self.id = id; self.side = side; self.dir = dir; self.centerLocal = centerLocal
    }
}

public enum MetalNodeHit: Sendable, Equatable {
    case none
    case body
    case port(id: String)
}

public protocol MetalCanvasNode: AnyObject {
    var id: String { get }
    /// Node rectangle in document space (top-left origin).
    var frameDoc: CGRect { get set }
    /// Ports in node-local space; the canvas maps to doc-space via `frameDoc`.
    func portLayout() -> [MetalNodePort]
    /// Hit-test a point in document space.
    func hitTest(doc: CGPoint) -> MetalNodeHit
    /// Encode Metal commands to render the node body in document space using a shared encoder.
    func encode(into view: MTKView, device: MTLDevice, encoder: MTLRenderCommandEncoder, transform: MetalCanvasTransform)
}

public extension MetalCanvasNode {
    func hitTest(doc: CGPoint) -> MetalNodeHit {
        return frameDoc.contains(doc) ? .body : .none
    }
    func encode(into view: MTKView, device: MTLDevice, encoder: MTLRenderCommandEncoder, transform: MetalCanvasTransform) {
        // Default no-op; concrete nodes draw their body.
    }
}

public struct MetalCanvasTransform: Sendable {
    public var zoom: Float
    public var translation: SIMD2<Float>
    public var drawableSize: SIMD2<Float>
    public init(zoom: Float, translation: SIMD2<Float>, drawableSize: SIMD2<Float>) {
        self.zoom = zoom; self.translation = translation; self.drawableSize = drawableSize
    }
    @inlinable public func docToNDC(x: CGFloat, y: CGFloat) -> SIMD2<Float> {
        let z = max(0.0001, zoom)
        let vx = Float(x) * z + translation.x
        let vy = Float(y) * z + translation.y
        let ndcX = (vx / max(1, drawableSize.x)) * 2 - 1
        let ndcY = 1 - (vy / max(1, drawableSize.y)) * 2
        return SIMD2<Float>(ndcX, ndcY)
    }
}

#endif
