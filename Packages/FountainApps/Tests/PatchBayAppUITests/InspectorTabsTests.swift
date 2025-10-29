import XCTest
@testable import patchbay_app

@MainActor
final class InspectorTabsTests: XCTestCase {
    func testTabsShapeAndDefaults() {
        // Only Chat and Stellwerk are present (no Instruments)
        let all = patchbay_app.InspectorPane.Tab.allCases
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first, .chat)
        XCTAssertEqual(all.last, .corpus)
        // RawValue mapping rejects legacy value
        XCTAssertNil(patchbay_app.InspectorPane.Tab(rawValue: "Instruments"))
    }
}

