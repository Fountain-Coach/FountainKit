import XCTest
@testable import patchbay_app

@MainActor
final class GraphRoundTripTests: XCTestCase {
    func testGraphDocRoundTripNodesAndEdges() {
        // Prepare VM with a small scene
        let vm1 = EditorVM()
        vm1.grid = 24
        vm1.nodes = [
            PBNode(id: "Node_1", title: "One", x: 48, y: 72, w: 200, h: 120, ports: [
                .init(id: "in", side: .left, dir: .input, type: "data"),
                .init(id: "out", side: .right, dir: .output, type: "data")
            ]),
            PBNode(id: "Node_2", title: "Two", x: 320, y: 200, w: 220, h: 140, ports: [
                .init(id: "in", side: .left, dir: .input, type: "data"),
                .init(id: "out", side: .right, dir: .output, type: "data")
            ]),
        ]
        vm1.edges = [ PBEdge(from: "Node_1.out", to: "Node_2.in") ]

        // Instruments minimal set to carry identity/schema (fake but sufficient)
        let schema = Components.Schemas.PropertySchema(version: 1, properties: [
            .init(name: "gain", _type: .float)
        ])
        let ident = Components.Schemas.InstrumentIdentity(manufacturer: "Fountain", product: "Mock", displayName: "Mock#1", instanceId: "m1", muid28: 0, hasUMPInput: true, hasUMPOutput: true)
        let i1 = Components.Schemas.Instrument(id: "Node_1", kind: .init(rawValue: "mvk.triangle")!, title: "One", x: 48, y: 72, w: 200, h: 120, identity: ident, propertySchema: schema)
        let i2 = Components.Schemas.Instrument(id: "Node_2", kind: .init(rawValue: "mvk.quad")!, title: "Two", x: 320, y: 200, w: 220, h: 140, identity: ident, propertySchema: schema)

        let doc = vm1.toGraphDoc(with: [i1, i2])

        // Apply to a fresh VM and compare
        let vm2 = EditorVM()
        vm2.applyGraphDoc(doc)

        XCTAssertEqual(vm2.grid, vm1.grid)
        XCTAssertEqual(vm2.nodes.count, vm1.nodes.count)
        XCTAssertEqual(Set(vm2.nodes.map{ $0.id }), Set(vm1.nodes.map{ $0.id }))
        // Positions should match
        for n in vm2.nodes {
            let ref = vm1.node(by: n.id)!
            XCTAssertEqual(n.x, ref.x)
            XCTAssertEqual(n.y, ref.y)
            XCTAssertEqual(n.w, ref.w)
            XCTAssertEqual(n.h, ref.h)
        }
        // Edges should match
        XCTAssertEqual(Set(vm2.edges.map{ "\($0.from)->\($0.to)" }), Set(vm1.edges.map{ "\($0.from)->\($0.to)" }))
    }
}

