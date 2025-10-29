import XCTest
@testable import qc_mock_service
import QCMockServiceCore

final class QCMockHandlersTests: XCTestCase {
    var core: ServiceCore! = nil
    var handlers: QCMockHandlers! = nil

    override func setUp() async throws {
        core = ServiceCore(docWidth: 1000, docHeight: 800, gridStep: 20)
        handlers = QCMockHandlers(core: core)
    }

    func testHealth() async throws {
        let out = try await handlers.getHealth(.init())
        guard case let .ok(ok) = out else { return XCTFail("Expected 200 OK") }
        let payload = try ok.body.json
        XCTAssertEqual(payload.status, .ok)
    }

    func testCanvasZoomAndPan() async throws {
        // Initial state
        do {
            let out = try await handlers.getCanvas(.init())
            guard case let .ok(ok) = out else { return XCTFail("Expected canvas 200") }
            let s = try ok.body.json
            XCTAssertEqual(s.docWidth, 1000)
            XCTAssertEqual(s.docHeight, 800)
            XCTAssertEqual(s.gridStep, 20)
        }
        // Zoom set to 2.0
        _ = try await handlers.zoomSet(.init(body: .json(.init(scale: 2.0, anchorView: nil))))
        // Pan by (10, -5)
        _ = try await handlers.panBy(.init(body: .json(.init(dx: 10, dy: -5))))
        // Verify
        let out2 = try await handlers.getCanvas(.init())
        guard case let .ok(ok2) = out2 else { return XCTFail("Expected canvas 200") }
        let s2 = try ok2.body.json
        XCTAssertEqual(s2.transform.scale, 2.0, accuracy: 0.0001)
        XCTAssertEqual(s2.transform.translation.x, 10.0, accuracy: 0.0001)
        XCTAssertEqual(s2.transform.translation.y, -5.0, accuracy: 0.0001)
    }

    func testNodesAndEdgesCrud() async throws {
        // Create a node
        let node = Components.Schemas.Node(id: "n1", title: "A", x: 10, y: 20, w: 120, h: 80, ports: [])
        let created = try await handlers.createNode(.init(body: .json(.init(id: node.id, title: node.title, x: node.x, y: node.y, w: node.w, h: node.h, ports: []))))
        guard case let .created(createdResp) = created else { return XCTFail("Expected 201 Created") }
        let n1 = try createdResp.body.json
        XCTAssertEqual(n1.id, node.id)

        // Add a port
        let port = Components.Schemas.Port(id: "p1", side: .left, dir: .out, _type: .data)
        let upd = try await handlers.addPort(.init(path: .init(id: node.id), headers: .init(), body: .json(port)))
        guard case let .ok(updResp) = upd else { return XCTFail("Expected 200 OK after addPort") }
        let n2 = try updResp.body.json
        XCTAssertEqual(n2.ports.count, 1)

        // Create an edge
        let ce = Components.Schemas.CreateEdge(from: "n1.p1", to: "n1.p1", routing: .qcBezier)
        let edgeCreated = try await handlers.createEdge(.init(body: .json(ce)))
        guard case let .created(edgeResp) = edgeCreated else { return XCTFail("Expected 201 Created for edge") }
        _ = try edgeResp.body.json
        // List edges
        let edgesOut = try await handlers.listEdges(.init())
        guard case let .ok(edgesOK) = edgesOut else { return XCTFail("Expected 200 edges") }
        let arr = try edgesOK.body.json
        XCTAssertEqual(arr.count, 1)

        // Export and import JSON roundtrip
        let docOut = try await handlers.exportJSON(.init())
        guard case let .ok(docOK) = docOut else { return XCTFail("Expected 200 export JSON") }
        let doc = try docOK.body.json
        // Wipe state via import (same doc as a no-op)
        _ = try await handlers.importJSON(.init(body: .json(doc)))

        // Remove port
        let rem = try await handlers.removePort(.init(path: .init(id: node.id, portId: port.id)))
        guard case let .ok(remOK) = rem else { return XCTFail("Expected 200 after removePort") }
        let n3 = try remOK.body.json
        XCTAssertEqual(n3.ports.count, 0)
    }
}

#endif // !ROBOT_ONLY
// Robot-only mode: exclude this suite when building robot tests
#if !ROBOT_ONLY
