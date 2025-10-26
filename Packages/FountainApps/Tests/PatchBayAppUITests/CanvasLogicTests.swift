import XCTest
@testable import patchbay_app

@MainActor
final class CanvasLogicTests: XCTestCase {
    func testGridDecimationThresholds() {
        // grid=24, scale=0.2 -> minor=4.8 (false), major=24 (true)
        var v = EditorVM.gridVisibility(scale: 0.2, grid: 24)
        XCTAssertFalse(v.showMinor)
        XCTAssertTrue(v.showLabels)
        // scale=0.5 -> minor=12 (true), major=60 (true)
        v = EditorVM.gridVisibility(scale: 0.5, grid: 24)
        XCTAssertTrue(v.showMinor)
        XCTAssertTrue(v.showLabels)
    }

    func testSnapAfterDrag() {
        let vm = EditorVM()
        vm.grid = 24
        vm.zoom = 2.0
        vm.nodes = [PBNode(id: "A", title: "A", x: 10, y: 10, w: 100, h: 60)]
        // Simulate drag end at view delta (30,30) -> doc delta (15,15) -> position (25,25) -> snapped to (24,24)
        let idx = vm.nodeIndex(by: "A")!
        vm.nodes[idx].x = 10 + Int(30 / vm.zoom)
        vm.nodes[idx].y = 10 + Int(30 / vm.zoom)
        // snap
        let g = CGFloat(vm.grid)
        let x = CGFloat(vm.nodes[idx].x)
        let y = CGFloat(vm.nodes[idx].y)
        vm.nodes[idx].x = Int((round(x / g) * g))
        vm.nodes[idx].y = Int((round(y / g) * g))
        XCTAssertEqual(vm.nodes[idx].x, 24)
        XCTAssertEqual(vm.nodes[idx].y, 24)
    }

    func testConnectCreatesEdge() {
        let vm = EditorVM()
        vm.nodes = [
            PBNode(id: "A", title: "A", x: 0, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: "B", x: 100, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        vm.addEdge(from: ("A","out"), to: ("B","in"))
        XCTAssertEqual(vm.edges.count, 1)
        XCTAssertEqual(vm.edges[0].from, "A.out")
        XCTAssertEqual(vm.edges[0].to, "B.in")
    }

    func testZoomBounds() {
        let vm = EditorVM()
        vm.zoom = -1
        vm.zoom = max(0.25, min(3.0, vm.zoom))
        XCTAssertEqual(vm.zoom, 0.25)
        vm.zoom = 10
        vm.zoom = max(0.25, min(3.0, vm.zoom))
        XCTAssertEqual(vm.zoom, 3.0)
    }

    func testConnectModeWithOptionFanout() {
        let vm = EditorVM()
        vm.connectMode = true
        vm.nodes = [
            PBNode(id: "A", title: "A", x: 0, y: 0, w: 100, h: 60, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: "B", x: 100, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)]),
            PBNode(id: "C", title: "C", x: 200, y: 0, w: 100, h: 60, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        // Start from A.out
        vm.tapPort(nodeId: "A", portId: "out", dir: .output, optionFanout: false)
        // Connect to B.in (no Option)
        vm.tapPort(nodeId: "B", portId: "in", dir: .input, optionFanout: false)
        XCTAssertTrue(vm.edges.contains(where: { $0.from == "A.out" && $0.to == "B.in" }))
        // Start again from A.out and Option-connect to C.in (fanout)
        vm.tapPort(nodeId: "A", portId: "out", dir: .output, optionFanout: false)
        vm.tapPort(nodeId: "C", portId: "in", dir: .input, optionFanout: true)
        XCTAssertTrue(vm.edges.contains(where: { $0.from == "A.out" && $0.to == "C.in" }))
        // Double-click (break) C.in
        vm.breakConnection(at: "C", portId: "in")
        XCTAssertFalse(vm.edges.contains(where: { $0.to == "C.in" }))
    }

    func testFitZoomComputation() {
        // content bounds 200x100 into view 400x300 -> min(400/200=2, 300/100=3) = 2
        let view = CGSize(width: 400, height: 300)
        let content = CGRect(x: 0, y: 0, width: 200, height: 100)
        let z = EditorVM.computeFitZoom(viewSize: view, contentBounds: content, minZoom: 0.25, maxZoom: 3.0)
        XCTAssertEqual(z, 2.0, accuracy: 0.001)
    }

    func testFitCentersContent() {
        let view = CGSize(width: 400, height: 300)
        let content = CGRect(x: 100, y: 50, width: 200, height: 100)
        let z = EditorVM.computeFitZoom(viewSize: view, contentBounds: content)
        XCTAssertEqual(z, 2.0, accuracy: 0.001) // fits on width
        // Compute translation and verify center maps near view center
        let targetX = (view.width - z * content.width) / 2.0
        let targetY = (view.height - z * content.height) / 2.0
        let tx = targetX / z - content.minX
        let ty = targetY / z - content.minY
        let xf = CanvasTransform(scale: z, translation: CGPoint(x: tx, y: ty))
        let mid = CGPoint(x: content.midX, y: content.midY)
        let v = xf.docToView(mid)
        XCTAssertEqual(v.x, view.width/2.0, accuracy: 0.5)
        XCTAssertEqual(v.y, view.height/2.0, accuracy: 0.5)
    }

    func testContentBoundsDefaultSquareWithMargin() {
        let vm = EditorVM()
        vm.grid = 24
        vm.nodes.removeAll()
        let rect = vm.contentBounds(margin: 40)
        // Default square is grid*20 on each side, then inset negative by margin
        let expectedSide: CGFloat = CGFloat(24 * 20)
        XCTAssertEqual(rect.width, expectedSide + 80, accuracy: 0.001) // +2*margin
        XCTAssertEqual(rect.height, expectedSide + 80, accuracy: 0.001)
        XCTAssertEqual(rect.minX, -40, accuracy: 0.001)
        XCTAssertEqual(rect.minY, -40, accuracy: 0.001)
    }

    func testContentBoundsWithNodesIncludesMargin() {
        let vm = EditorVM()
        vm.grid = 24
        vm.nodes = [
            PBNode(id: "A", title: nil, x: 10, y: 20, w: 100, h: 50),
            PBNode(id: "B", title: nil, x: 300, y: 200, w: 80, h: 40)
        ]
        let rect = vm.contentBounds(margin: 40)
        XCTAssertEqual(rect.minX, -30, accuracy: 0.001) // 10 - 40
        XCTAssertEqual(rect.minY, -20, accuracy: 0.001) // 20 - 40
        XCTAssertEqual(rect.maxX, 420, accuracy: 0.001) // (300+80) + 40
        XCTAssertEqual(rect.maxY, 280, accuracy: 0.001) // (200+40) + 40
    }

    func testUniqueNodeIDIncrements() {
        let vm = EditorVM()
        vm.nodes = [PBNode(id: "Node_1", title: nil, x: 0, y: 0, w: 10, h: 10)]
        let a = vm.uniqueNodeID(prefix: "Node")
        vm.nodes.append(PBNode(id: a, title: nil, x: 0, y: 0, w: 10, h: 10))
        let b = vm.uniqueNodeID(prefix: "Node")
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(vm.nodes.contains(where: { $0.id == b }))
    }

    func testNudgeSelectedMovesByGridStep() {
        let vm = EditorVM()
        vm.grid = 24
        vm.nodes = [PBNode(id: "A", title: nil, x: 0, y: 0, w: 10, h: 10)]
        vm.selected = ["A"]
        vm.nudgeSelected(dx: 1, dy: 0) // one step to the right
        XCTAssertEqual(vm.node(by: "A")?.x, 24)
        XCTAssertEqual(vm.node(by: "A")?.y, 0)
        vm.nudgeSelected(dx: 0, dy: -1) // one step up (negative y)
        XCTAssertEqual(vm.node(by: "A")?.x, 24)
        XCTAssertEqual(vm.node(by: "A")?.y, -24)
    }

    func testNudgeMultipleSelection() {
        let vm = EditorVM()
        vm.grid = 10
        vm.nodes = [
            PBNode(id: "A", title: nil, x: 0, y: 0, w: 10, h: 10),
            PBNode(id: "B", title: nil, x: 5, y: -5, w: 10, h: 10)
        ]
        vm.selected = ["A", "B"]
        vm.nudgeSelected(dx: -2, dy: 3) // left 2, down 3
        XCTAssertEqual(vm.node(by: "A")?.x, -20)
        XCTAssertEqual(vm.node(by: "A")?.y, 30)
        XCTAssertEqual(vm.node(by: "B")?.x, -15)
        XCTAssertEqual(vm.node(by: "B")?.y, 25)
    }
}
