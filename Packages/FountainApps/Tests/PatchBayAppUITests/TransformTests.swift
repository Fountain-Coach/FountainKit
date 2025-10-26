import XCTest
@testable import patchbay_app

final class TransformTests: XCTestCase {
    func testDocViewRoundTripNoPadding() {
        let t = CanvasTransform(scale: 2.0, translation: CGPoint(x: 10, y: -5))
        let p = CGPoint(x: 123.4, y: -56.7)
        let v = t.docToView(p)
        let back = t.viewToDoc(v)
        XCTAssertEqual(back.x, p.x, accuracy: 0.001)
        XCTAssertEqual(back.y, p.y, accuracy: 0.001)
    }
}

