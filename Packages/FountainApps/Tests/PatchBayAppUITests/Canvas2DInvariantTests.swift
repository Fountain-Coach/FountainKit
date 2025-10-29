import XCTest
@testable import patchbay_app
import MetalViewKit
import SwiftUI

final class Canvas2DInvariantTests: XCTestCase {
    func testAnchorStableZoom() {
        var c = Canvas2D(zoom: 1.0, translation: .zero)
        let anchor = CGPoint(x: 320, y: 240)
        // Choose a doc point and compute its view position at z=1
        let d = CGPoint(x: 100, y: 80)
        let v0 = c.docToView(d)
        // Zoom around the view anchor
        c.zoomAround(viewAnchor: anchor, magnification: 0.25) // +25%
        // Re-project the same doc point
        let v1 = c.docToView(d)
        // The relative offset in view should change by the same factor from the anchor
        // But the anchor itself stays stationary. Within 1 px tolerance.
        XCTAssertLessThan(abs(v1.x - v0.x - (anchor.x - anchor.x)), 1.0)
        XCTAssertLessThan(abs(v1.y - v0.y - (anchor.y - anchor.y)), 1.0)
    }

    func testFollowFingerPan() {
        var c = Canvas2D(zoom: 2.0, translation: .zero)
        // A 20pt view delta should move translation by 10 doc units at 2x
        c.panBy(viewDelta: CGSize(width: 20, height: -30))
        XCTAssertEqual(c.translation.x, 10, accuracy: 0.001)
        XCTAssertEqual(c.translation.y, -15, accuracy: 0.001)
    }
}

