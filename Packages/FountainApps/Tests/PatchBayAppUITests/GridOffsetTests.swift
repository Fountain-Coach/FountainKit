import XCTest
@testable import patchbay_app

final class GridOffsetTests: XCTestCase {
    func testPeriodicOffsetWrapsAndIsPositive() {
        let step: CGFloat = 10
        let s: CGFloat = 2.0
        // translation in doc units of 5 -> view 10 -> offset 0
        XCTAssertEqual(GridBackground.periodicOffset(5, s, step), 0, accuracy: 0.001)
        // negative translation wraps into [0, step)
        let o = GridBackground.periodicOffset(-2.5, s, step) // view -5 -> wrap to 5
        XCTAssertEqual(o, 5, accuracy: 0.001)
    }
}

