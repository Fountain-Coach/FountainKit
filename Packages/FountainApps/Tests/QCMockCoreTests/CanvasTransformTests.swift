import XCTest
@testable import QCMockCore
import CoreGraphics

final class CanvasTransformTests: XCTestCase {
    func testRoundTrip() {
        var xf = CanvasTransform(scale: 2.0, translation: CGPoint(x: 10, y: -5))
        let p = CGPoint(x: 12.3, y: -7.7)
        let v = xf.docToView(p)
        let back = xf.viewToDoc(v)
        XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
    }

    func testAnchorZoomKeepsAnchorStable() {
        var xf = CanvasTransform(scale: 1.0, translation: .zero)
        let anchorView = CGPoint(x: 200, y: 150)
        let beforeDoc = xf.viewToDoc(anchorView)
        xf.zoom(around: anchorView, factor: 1.5)
        let afterView = xf.docToView(beforeDoc)
        XCTAssertEqual(afterView.x, anchorView.x, accuracy: 1e-5)
        XCTAssertEqual(afterView.y, anchorView.y, accuracy: 1e-5)
    }

    func testGridDecimation() {
        // minor step 24 doc units
        let step: CGFloat = 24
        // scale small: minorPx=6 <8 → hide minors; major=30>=12 → labels shown
        var dec = GridModel.decimation(minorStepDoc: step, scale: 0.25)
        XCTAssertFalse(dec.showMinor)
        XCTAssertTrue(dec.showLabels)
        // scale medium: minorPx=12 → show minors; major=60 → labels
        dec = GridModel.decimation(minorStepDoc: step, scale: 0.5)
        XCTAssertTrue(dec.showMinor)
        XCTAssertTrue(dec.showLabels)
    }

    func testNonScalingWidth() {
        // At 2x zoom, a 0.5 doc width should render as 1px
        let w = GridModel.nonScalingStrokeWidth(desiredPixels: 1.0, scale: 2.0)
        XCTAssertEqual(w, 0.5, accuracy: 1e-6)
    }
}

