import SwiftUI

// Canonical document <-> view mapping used by the canvas. Centralizes scale and translation.
struct CanvasTransform: Equatable, Sendable {
    var scale: CGFloat = 1.0
    var translation: CGPoint = .zero // in view pixels

    func docToView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + translation.x, y: p.y * scale + translation.y)
    }
    func viewToDoc(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - translation.x) / max(0.0001, scale), y: (p.y - translation.y) / max(0.0001, scale))
    }
    mutating func zoom(around viewAnchor: CGPoint, factor: CGFloat, min: CGFloat = 0.25, max: CGFloat = 4.0) {
        let oldScale = scale
        let newScale = Swift.min(max, Swift.max(min, scale * factor))
        guard abs(newScale - oldScale) > 0.0001 else { return }
        let anchorDoc = viewToDoc(viewAnchor)
        scale = newScale
        translation.x = viewAnchor.x - anchorDoc.x * scale
        translation.y = viewAnchor.y - anchorDoc.y * scale
    }
}

private struct CanvasTransformKey: EnvironmentKey { static let defaultValue = CanvasTransform() }
extension EnvironmentValues { var canvasTransform: CanvasTransform { get { self[CanvasTransformKey.self] } set { self[CanvasTransformKey.self] = newValue } } }

