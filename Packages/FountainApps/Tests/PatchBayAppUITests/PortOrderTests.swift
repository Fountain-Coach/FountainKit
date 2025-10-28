import XCTest
@testable import patchbay_app

final class PortOrderTests: XCTestCase {
    func testCanonicalSortPortsInputOrder() {
        let ports: [PBPort] = [
            .init(id: "z", side: .left, dir: .input),
            .init(id: "in", side: .left, dir: .input),
            .init(id: "umpIn", side: .left, dir: .input)
        ]
        let sorted = canonicalSortPorts(ports)
        XCTAssertEqual(sorted.map{ $0.id }, ["in","umpIn","z"])        
    }

    func testCanonicalSortPortsOutputOrder() {
        let ports: [PBPort] = [
            .init(id: "umpOut", side: .right, dir: .output),
            .init(id: "out", side: .right, dir: .output),
            .init(id: "a", side: .right, dir: .output)
        ]
        let sorted = canonicalSortPorts(ports)
        XCTAssertEqual(sorted.map{ $0.id }, ["out","umpOut","a"])        
    }
}

