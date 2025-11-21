import XCTest
import MetalViewKit
import CoreGraphics

final class InfinityCanvasTests: XCTestCase {
    func testPanByFollowFinger() {
        var canvas = Canvas2D(zoom: 1.0, translation: .zero)
        canvas.panBy(viewDelta: CGSize(width: 10, height: -5))
        XCTAssertEqual(canvas.translation, CGPoint(x: 10, y: -5))
    }

    func testZoomAroundKeepsAnchorStable() {
        var canvas = Canvas2D(zoom: 1.0, translation: .zero)
        let docPoint = CGPoint(x: 120, y: -40)
        let anchor = canvas.docToView(docPoint)

        canvas.zoomAround(viewAnchor: anchor, magnification: 0.5)

        let after = canvas.docToView(docPoint)
        let epsilon: CGFloat = 1e-6
        XCTAssertEqual(after.x, anchor.x, accuracy: epsilon)
        XCTAssertEqual(after.y, anchor.y, accuracy: epsilon)
    }

    func testZoomClampsToConfiguredBounds() {
        var canvas = Canvas2D(zoom: canvasMaxZoom(), translation: .zero)
        canvas.zoomAround(viewAnchor: .zero, magnification: 10.0)
        XCTAssertEqual(canvas.zoom, canvas.maxZoom)

        canvas.zoom = canvasMinZoom()
        canvas.zoomAround(viewAnchor: .zero, magnification: -0.9)
        XCTAssertEqual(canvas.zoom, canvas.minZoom)
    }

    private func canvasMaxZoom() -> CGFloat {
        let canvas = Canvas2D()
        return canvas.maxZoom
    }

    private func canvasMinZoom() -> CGFloat {
        let canvas = Canvas2D()
        return canvas.minZoom
    }
}

final class InfinityGraphTests: XCTestCase {
    func testAddingNodeSnapsToGridAndSelects() {
        var scene = InfinityScene()
        scene.grid = 10

        let updated = scene.addingNode(at: CGPoint(x: 12, y: 17), baseTitle: "Node")
        XCTAssertEqual(updated.nodes.count, 1)

        guard let node = updated.nodes.first else {
            XCTFail("expected a node after addingNode")
            return
        }

        XCTAssertEqual(node.x % scene.grid, 0)
        XCTAssertEqual(node.y % scene.grid, 0)
        XCTAssertTrue(updated.selection.contains(node.id))
        XCTAssertEqual(node.title, "Node")
    }

    func testMovingNodeAppliesDocumentDelta() {
        var scene = InfinityScene()
        scene.grid = 10
        scene = scene.addingNode(at: CGPoint(x: 20, y: 40), baseTitle: "Node")

        guard let original = scene.nodes.first else {
            XCTFail("expected node before move")
            return
        }

        let moved = scene.movingNode(id: original.id, by: CGPoint(x: 5, y: -10))
        guard let node = moved.node(id: original.id) else {
            XCTFail("expected node after move")
            return
        }

        XCTAssertEqual(node.x, original.x + 5)
        XCTAssertEqual(node.y, original.y - 10)
    }

    func testEnsuringEdgeIsIdempotent() {
        var scene = InfinityScene()
        scene.grid = 10
        scene = scene.addingNode(at: CGPoint(x: 0, y: 0), baseTitle: "A")
        scene = scene.addingNode(at: CGPoint(x: 50, y: 0), baseTitle: "B")

        guard scene.nodes.count == 2 else {
            XCTFail("expected two nodes")
            return
        }
        let fromId = scene.nodes[0].id
        let toId = scene.nodes[1].id

        let once = scene.ensuringEdge(from: (fromId, "out"), to: (toId, "in"))
        XCTAssertEqual(once.edges.count, 1)

        let twice = once.ensuringEdge(from: (fromId, "out"), to: (toId, "in"))
        XCTAssertEqual(twice.edges.count, 1)

        guard let edge = twice.edges.first else {
            XCTFail("expected an edge after ensuringEdge")
            return
        }
        XCTAssertEqual(edge.fromNodeId, fromId)
        XCTAssertEqual(edge.toNodeId, toId)
        XCTAssertEqual(edge.fromPortId, "out")
        XCTAssertEqual(edge.toPortId, "in")
    }

    func testPortPositionMatchesNodeFrameSides() {
        let node = InfinityNode(
            id: "n1",
            title: "Node",
            x: 10,
            y: 20,
            width: 100,
            height: 40,
            ports: []
        )
        var scene = InfinityScene()
        scene.nodes = [node]

        let left = InfinityPort(id: "pL", side: .left, direction: .input)
        let right = InfinityPort(id: "pR", side: .right, direction: .output)
        let top = InfinityPort(id: "pT", side: .top, direction: .input)
        let bottom = InfinityPort(id: "pB", side: .bottom, direction: .output)

        XCTAssertEqual(scene.portPosition(node: node, port: left), CGPoint(x: 10, y: 40))
        XCTAssertEqual(scene.portPosition(node: node, port: right), CGPoint(x: 110, y: 40))
        XCTAssertEqual(scene.portPosition(node: node, port: top), CGPoint(x: 60, y: 20))
        XCTAssertEqual(scene.portPosition(node: node, port: bottom), CGPoint(x: 60, y: 60))
    }
}
