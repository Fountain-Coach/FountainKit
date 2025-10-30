import XCTest
@testable import patchbay_app

@MainActor
final class InitialFitFixtureTests: XCTestCase {
    struct Fixture: Decodable {
        let viewWidth: CGFloat
        let viewHeight: CGFloat
        let pageWidth: CGFloat
        let pageHeight: CGFloat
        let expectedZoom: CGFloat
        let expectedTranslationX: CGFloat
        let expectedTranslationY: CGFloat
        let toleranceZoom: CGFloat
        let toleranceTranslation: CGFloat
    }

    func testInitialFitMatchesFixture() throws {
        let url = Bundle.module.url(forResource: "initial-fit-a4-portrait-1200x900", withExtension: "json", subdirectory: "Fixtures") ?? {
            // Fallback: resolve from source tree to avoid bundle resource issues
            let here = URL(fileURLWithPath: #filePath)
            return here.deletingLastPathComponent().appendingPathComponent("Fixtures/initial-fit-a4-portrait-1200x900.json")
        }()
        let data = try Data(contentsOf: url)
        let f = try JSONDecoder().decode(Fixture.self, from: data)
        let view = CGSize(width: f.viewWidth, height: f.viewHeight)
        let page = CGRect(origin: .zero, size: CGSize(width: f.pageWidth, height: f.pageHeight))
        let z = EditorVM.computeFitZoom(viewSize: view, contentBounds: page)
        let t = EditorVM.computeCenterTranslation(viewSize: view, contentBounds: page, zoom: z)
        XCTAssertEqual(z, f.expectedZoom, accuracy: f.toleranceZoom)
        XCTAssertEqual(t.x, f.expectedTranslationX, accuracy: f.toleranceTranslation)
        XCTAssertEqual(t.y, f.expectedTranslationY, accuracy: f.toleranceTranslation)
    }
}
