import Foundation
import CoreGraphics
import QCMockServiceCore

@main
struct Runner {
    static func main() {
        var failures = 0
        func assert(_ cond: @autoclosure () -> Bool, _ name: String) { if !cond() { failures += 1; fputs("FAIL: \(name)\n", stderr) } else { print("PASS: \(name)") } }

        let svc = ServiceCore(docWidth: 1000, docHeight: 800, gridStep: 24)
        // Canvas
        assert(svc.getCanvas().gridStep == 24, "canvas.gridStep")
        svc.patchCanvas(gridStep: 32)
        assert(svc.getCanvas().gridStep == 32, "canvas.patchGrid")
        // Zoom fit / actual
        svc.zoomFit()
        assert(svc.getCanvas().transform.scale == 1.0, "zoom.fit")
        svc.zoomSet(scale: 2.0, anchorView: CGPoint(x: 200, y: 150))
        assert(abs(svc.getCanvas().transform.scale - 2.0) < 1e-6, "zoom.set")
        let beforeX = svc.getCanvas().transform.translation.x
        svc.panBy(dx: 50, dy: -30)
        let afterX = svc.getCanvas().transform.translation.x
        assert(abs((afterX - beforeX) - 50) < 1e-6, "pan.dx")
        // Nodes CRUD
        _ = svc.createNode(.init(id: "A", title: "A", x: 10, y: 10, w: 120, h: 80, ports: []))
        assert(svc.getNode("A") != nil, "nodes.create")
        _ = svc.addPort(nodeId: "A", port: .init(id: "out", side: "right", dir: "out", type: "data"))
        assert(svc.getNode("A")!.ports.count == 1, "nodes.addPort")
        _ = svc.patchNode("A", title: "AA", x: 20)
        assert(svc.getNode("A")!.title == "AA" && svc.getNode("A")!.x == 20, "nodes.patch")
        // Edges
        _ = svc.createEdge(.init(id: "E", from: "A.out", to: "B.in", routing: "qcBezier", width: 2.0, glow: false))
        assert(svc.listEdges().count == 1, "edges.create")
        // Export/Import
        let doc = svc.exportJSON()
        let svc2 = ServiceCore()
        svc2.importJSON(doc)
        assert(svc2.listNodes().count == svc.listNodes().count && svc2.listEdges().count == svc.listEdges().count, "import/export roundtrip")
        if failures > 0 { fputs("FAILURES: \(failures)\n", stderr); exit(1) }
        print("ALL PASS")
    }
}
