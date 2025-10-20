import XCTest
@testable import MemChatKit

final class VisualCoverageTests: XCTestCase {
    func testUnionAreaDisjoint() throws {
        let r1 = CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1)
        let r2 = CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)
        let a = VisualCoverageUtils.unionAreaNormalized([r1, r2])
        XCTAssertEqual(a, 0.02, accuracy: 1e-6)
    }

    func testUnionAreaOverlap() throws {
        let r1 = CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        let r2 = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        // Areas: r1=0.16, r2=0.16, overlap=(0.2*0.2)=0.04 => union=0.28
        let a = VisualCoverageUtils.unionAreaNormalized([r1, r2])
        XCTAssertEqual(a, 0.28, accuracy: 1e-6)
    }

    func testUnionAreaClamps() throws {
        let r = CGRect(x: -0.1, y: 0.9, width: 0.4, height: 0.4) // partially outside
        let a = VisualCoverageUtils.unionAreaNormalized([r])
        // Clamped rect becomes x=0,y=0.9,w=0.4,h=0.1 => area=0.04
        XCTAssertEqual(a, 0.04, accuracy: 1e-6)
    }
}

