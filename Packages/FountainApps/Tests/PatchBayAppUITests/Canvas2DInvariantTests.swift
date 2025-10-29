import XCTest
@testable import patchbay_app
import MetalViewKit
import SwiftUI

@MainActor
final class Canvas2DInvariantTests: XCTestCase {
    func testAnchorStableZoom() {
        var c = Canvas2D(zoom: 1.0, translation: .zero)
        let anchor = CGPoint(x: 320, y: 240)
        // Compute the doc point currently under the anchor
        let d = c.viewToDoc(anchor)
        // Zoom around the view anchor
        c.zoomAround(viewAnchor: anchor, magnification: 0.25) // +25%
        // The same doc point should still map to the anchor within tolerance
        let v = c.docToView(d)
        XCTAssertLessThan(abs(v.x - anchor.x), 1.0)
        XCTAssertLessThan(abs(v.y - anchor.y), 1.0)
    }

    func testFollowFingerPan() {
        var c = Canvas2D(zoom: 2.0, translation: .zero)
        // A 20pt view delta should move translation by 10 doc units at 2x
        c.panBy(viewDelta: CGSize(width: 20, height: -30))
        XCTAssertEqual(c.translation.x, 10, accuracy: 0.001)
        XCTAssertEqual(c.translation.y, -15, accuracy: 0.001)
    }
}
