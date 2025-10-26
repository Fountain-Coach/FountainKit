import CoreGraphics

struct CanvasTransform {
    var scale: CGFloat
    var translation: CGPoint

    func docToView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x + translation.x) * scale, y: (p.y + translation.y) * scale)
    }
    func viewToDoc(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x / max(0.0001, scale)) - translation.x,
                y: (p.y / max(0.0001, scale)) - translation.y)
    }
}

