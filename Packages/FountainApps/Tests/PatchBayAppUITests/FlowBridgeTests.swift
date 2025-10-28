import XCTest
@testable import patchbay_app

final class FlowBridgeTests: XCTestCase {
    func testToFlowPatchWithDuplicateIdsDoesNotCrash() {
        let vm = EditorVM()
        vm.nodes = [
            PBNode(id: "dup", title: "dup1", x: 0, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "b", title: "b", x: 200, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)]),
            PBNode(id: "dup", title: "dup2", x: 400, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)])
        ]
        vm.edges = [ PBEdge(from: "dup.out", to: "b.in") ]
        let patch = FlowBridge.toFlowPatch(vm: vm)
        XCTAssertEqual(patch.nodes.count, 3)
        XCTAssertEqual(patch.wires.count, 1)
        // Validate that wire indexes are in range
        let w = patch.wires.first!
        XCTAssertLessThan(w.output.nodeIndex, patch.nodes.count)
        XCTAssertLessThan(w.input.nodeIndex, patch.nodes.count)
    }
}

