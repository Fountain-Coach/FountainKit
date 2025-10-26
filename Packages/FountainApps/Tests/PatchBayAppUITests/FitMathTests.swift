import XCTest
@testable import patchbay_app

@MainActor
final class FitMathTests: XCTestCase {
    func testComputeCenterTranslationCentersContent() {
        let view = CGSize(width: 1200, height: 900)
        let doc = CGRect(origin: .zero, size: CGSize(width: 600, height: 800))
        let z = EditorVM.computeFitZoom(viewSize: view, contentBounds: doc)
        let t = EditorVM.computeCenterTranslation(viewSize: view, contentBounds: doc, zoom: z)
        let xf = CanvasTransform(scale: z, translation: t)
        let center = CGPoint(x: doc.midX, y: doc.midY)
        let v = xf.docToView(center)
        XCTAssertEqual(v.x, view.width/2.0, accuracy: 0.75)
        XCTAssertEqual(v.y, view.height/2.0, accuracy: 0.75)
    }
}
