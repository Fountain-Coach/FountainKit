import XCTest
import SwiftUI
@testable import patchbay_app

@MainActor
final class EditorCanvasDeleteTests: XCTestCase {
    func testPbDeleteRemovesSelectedNodesAndIncidentEdges() async throws {
        let vm = EditorVM()
        let state = AppState()
        // Build a small graph: A -> B, C isolated
        vm.nodes = [
            PBNode(id: "A", title: nil, x: 0, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: nil, x: 200, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)]),
            PBNode(id: "C", title: nil, x: 400, y: 0, w: 100, h: 60)
        ]
        vm.edges = [PBEdge(from: "A.out", to: "B.in")]
        vm.selected = ["A", "C"]
        vm.selection = "A"

        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()

        // Post delete; expect A and C removed, and edge gone.
        NotificationCenter.default.post(name: .pbDelete, object: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(vm.nodes.map { $0.id }.sorted(), ["B"]) // only B remains
        XCTAssertTrue(vm.edges.isEmpty)
        XCTAssertTrue(vm.selected.isEmpty)
        XCTAssertNil(vm.selection)
    }
}

