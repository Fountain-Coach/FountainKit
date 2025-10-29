import XCTest
import SwiftUI
@testable import FountainFlow

final class StageGeometryTests: XCTestCase {
    func testBaselineCountA4() {
        let m = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        XCTAssertEqual(StageGeometry.baselineCount(page: "A4", margins: m, baseline: 12), 67)
    }
    func testBaselineCountLetter() {
        let m = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        XCTAssertEqual(StageGeometry.baselineCount(page: "Letter", margins: m, baseline: 12), 63)
    }
    func testTickFractionsMonotonic() {
        let f = StageOverlayGeometry.baselineFractions(count: 5)
        XCTAssertEqual(f.count, 5)
        for i in 1..<f.count { XCTAssertGreaterThan(f[i], f[i-1]) }
        XCTAssertGreaterThan(f.first!, 0)
        XCTAssertLessThan(f.last!, 1)
    }
    func testDocTickYsBounds() {
        let r = CGRect(x: 100, y: 200, width: 400, height: 600)
        let ys = StageOverlayGeometry.docTickYs(rect: r, count: 10)
        XCTAssertEqual(ys.count, 10)
        XCTAssertGreaterThanOrEqual(ys.min() ?? 0, r.minY)
        XCTAssertLessThanOrEqual(ys.max() ?? 0, r.maxY)
    }
}
