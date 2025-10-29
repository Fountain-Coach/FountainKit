import XCTest
import Flow
@testable import FountainFlow

final class PatchOpsTests: XCTestCase {
    func testSplitPreservesInternalWires() {
        // nodes: A(stage), B(rest), C(stage)
        let A = Node(name: "A", position: .zero, inputs: ["in"], outputs: ["out"])
        let B = Node(name: "B", position: .zero, inputs: ["in"], outputs: ["out"])
        let C = Node(name: "C", position: .zero, inputs: ["in"], outputs: ["out"])
        let nodes = [A,B,C]
        // wires: A->C (stage↔stage), A->B (cross), B->B (rest↔rest)
        let wStage = Wire(from: OutputID(0,0), to: InputID(2,0))
        let wCross = Wire(from: OutputID(0,0), to: InputID(1,0))
        let wRest = Wire(from: OutputID(1,0), to: InputID(1,0))
        let patch = Patch(nodes: nodes, wires: [wStage,wCross,wRest])
        let (stage, rest) = FountainFlowPatchOps.split(patch: patch, isStage: { [0,2].contains($0) })
        // stage nodes are [A,C]; wires only A->C remains
        XCTAssertEqual(stage.nodes.count, 2)
        XCTAssertTrue(stage.wires.contains(Wire(from: OutputID(0,0), to: InputID(1,0))))
        XCTAssertEqual(stage.wires.count, 1)
        // rest nodes are [B]; wires only B->B remains
        XCTAssertEqual(rest.nodes.count, 1)
        XCTAssertTrue(rest.wires.contains(Wire(from: OutputID(0,0), to: InputID(0,0))))
        XCTAssertEqual(rest.wires.count, 1)
    }
}

