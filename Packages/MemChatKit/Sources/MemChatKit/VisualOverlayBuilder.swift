import Foundation
import SemanticBrowserAPI
import SwiftUI

enum VisualOverlayBuilder {
    static func overlays(from analysis: SemanticBrowserAPI.Components.Schemas.Analysis, imageId: String) -> [EvidenceMapView.Overlay] {
        var out: [EvidenceMapView.Overlay] = []
        for b in analysis.blocks {
            if let rects = b.rects {
                for (i, r) in rects.enumerated() {
                    guard r.imageId == imageId else { continue }
                    let x = CGFloat(r.x ?? 0)
                    let y = CGFloat(r.y ?? 0)
                    let w = CGFloat(r.w ?? 0)
                    let h = CGFloat(r.h ?? 0)
                    guard w > 0, h > 0 else { continue }
                    let rect = CGRect(x: x, y: y, width: w, height: h)
                    out.append(.init(id: "\(b.id)-\(i)", rect: rect, color: .green))
                }
            }
        }
        return out
    }
}

