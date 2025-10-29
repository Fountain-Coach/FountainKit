import XCTest
@testable import patchbay_app

@MainActor
final class EditorVMDeletionTests: XCTestCase {
    func testDeleteSingleNodeRemovesIncidentEdges() {
        let vm = EditorVM()
        vm.nodes = [
            PBNode(id: "A", title: nil, x: 0, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: nil, x: 200, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        vm.edges = [ PBEdge(from: "A.out", to: "B.in") ]
        vm.deleteNodes(ids: ["A"])        
        XCTAssertEqual(vm.nodes.map{ $0.id }, ["B"])        
        XCTAssertTrue(vm.edges.isEmpty)
        XCTAssertNil(vm.selection)
        XCTAssertTrue(vm.selected.isEmpty)
    }

    func testDeleteMultiSelectionRemovesAllEdges() {
        let vm = EditorVM()
        vm.nodes = [
            PBNode(id: "A", title: nil, x: 0, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: nil, x: 200, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input), .init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "C", title: nil, x: 400, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        vm.edges = [
            PBEdge(from: "A.out", to: "B.in"),
            PBEdge(from: "B.out", to: "C.in")
        ]
        vm.selected = ["A","B"]
        vm.selection = "B"
        vm.deleteNodes(ids: vm.selected)
        XCTAssertEqual(vm.nodes.map{ $0.id }, ["C"])        
        XCTAssertTrue(vm.edges.isEmpty)
        XCTAssertNil(vm.selection)
        XCTAssertTrue(vm.selected.isEmpty)
    }
}
