import XCTest
@testable import QuietFrameKit

final class VendorJSONTests: XCTestCase {
    func testEncodeParse_recStart() {
        let bytes = QFVendorJSON.encode(topic: "rec.start")
        let cmd = QFVendorJSON.parse(bytes)
        XCTAssertEqual(cmd, .recStart)
    }

    func testEncodeParse_recStop() {
        let bytes = QFVendorJSON.encode(topic: "rec.stop")
        let cmd = QFVendorJSON.parse(bytes)
        XCTAssertEqual(cmd, .recStop)
    }

    func testParse_unknown() {
        let bytes = QFVendorJSON.encode(topic: "custom.topic", data: ["a": 1])
        let cmd = QFVendorJSON.parse(bytes)
        switch cmd {
        case .unknown(let t):
            XCTAssertEqual(t, "custom.topic")
        default:
            XCTFail("Expected unknown topic")
        }
    }
}

