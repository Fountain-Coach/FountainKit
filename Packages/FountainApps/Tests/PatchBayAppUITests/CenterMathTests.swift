import XCTest
@testable import patchbay_app

final class CenterMathTests: XCTestCase {
    func testFrameCenterTranslationCentersDocWithinPageFrame() {
        // Given a page and a view that centers the page frame via padding
        let view = CGSize(width: 900, height: 600)
        let page = CGSize(width: 600, height: 400)
        // fit zoom on width -> z = 900/600 = 1.5, but height 600/400 = 1.5 too => z=1.5
        let z = EditorVM.computeFitZoom(viewSize: view, contentBounds: CGRect(origin: .zero, size: page))
        XCTAssertEqual(z, 1.5, accuracy: 0.001)
        let padX = (view.width - page.width) * 0.5 // 150
        let padY = (view.height - page.height) * 0.5 // 100
        let t = EditorVM.computeFrameCenterTranslation(pageSize: page, zoom: z)
        let xf = CanvasTransform(scale: z, translation: t)
        let docCenter = CGPoint(x: page.width/2, y: page.height/2)
        let v = xf.docToView(docCenter)
        // Add page frame padding offsets
        let vx = v.x + padX
        let vy = v.y + padY
        XCTAssertEqual(vx, view.width/2.0, accuracy: 0.75)
        XCTAssertEqual(vy, view.height/2.0, accuracy: 0.75)
    }
}

