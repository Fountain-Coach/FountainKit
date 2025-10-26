import XCTest
@testable import patchbay_app

@MainActor
final class PageSpecTests: XCTestCase {
    func testA4PortraitPoints() {
        let sz = PageSpec.a4Portrait
        XCTAssertEqual(sz.width, 595.28, accuracy: 0.5)
        XCTAssertEqual(sz.height, 841.89, accuracy: 0.5)
    }

    func testFitToPageComputesExpectedZoom() {
        let vm = EditorVM()
        vm.pageSize = PageSpec.a4Portrait
        // View 1190x841.89 -> should fit by height (zoom ~ 1.0)
        let view = CGSize(width: 1190.0, height: 841.89)
        let content = CGRect(origin: .zero, size: vm.pageSize)
        let z = EditorVM.computeFitZoom(viewSize: view, contentBounds: content)
        XCTAssertEqual(z, 1.0, accuracy: 0.01)
    }
}
