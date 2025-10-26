import CoreGraphics

public struct CanvasTransform: Equatable, Sendable {
    public var scale: CGFloat
    public var translation: CGPoint // in view pixels
    public init(scale: CGFloat = 1.0, translation: CGPoint = .zero) { self.scale = scale; self.translation = translation }
    @inlinable public func docToView(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + translation.x, y: p.y * scale + translation.y) }
    @inlinable public func viewToDoc(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - translation.x) / max(0.0001, scale), y: (p.y - translation.y) / max(0.0001, scale)) }
    @inlinable public mutating func zoom(around viewAnchor: CGPoint, factor: CGFloat, min: CGFloat = 0.25, max: CGFloat = 4.0) {
        let old = scale
        let next = Swift.min(max, Swift.max(min, scale * factor))
        guard abs(next - old) > 0.0001 else { return }
        let anchorDoc = viewToDoc(viewAnchor)
        scale = next
        translation.x = viewAnchor.x - anchorDoc.x * scale
        translation.y = viewAnchor.y - anchorDoc.y * scale
    }
}

public enum GridModel {
    // Decide whether to show minor grid lines and numeric labels based on pixel density
    public static func decimation(minorStepDoc: CGFloat, scale: CGFloat) -> (showMinor: Bool, showLabels: Bool) {
        let minorPx = minorStepDoc * scale
        let majorPx = minorPx * 5.0
        return (minorPx >= 8.0, majorPx >= 12.0)
    }
    // Compute a stroke width in doc units that renders as desired pixels in view
    public static func nonScalingStrokeWidth(desiredPixels: CGFloat, scale: CGFloat) -> CGFloat {
        desiredPixels / max(0.0001, scale)
    }
}

