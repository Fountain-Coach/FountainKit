import Foundation
import OpenAPIRuntime
import QCMockServiceCore

// Internal server-side handlers conforming to the generated APIProtocol.
final class QCMockHandlers: APIProtocol, @unchecked Sendable {
    let core: ServiceCore

    init(core: ServiceCore = ServiceCore()) { self.core = core }

    // MARK: - Health
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        .ok(.init(body: .json(.init(status: .ok))))
    }

    // MARK: - Canvas
    func getCanvas(_ input: Operations.getCanvas.Input) async throws -> Operations.getCanvas.Output {
        .ok(.init(body: .json(toSchema(core.getCanvas()))))
    }

    func patchCanvas(_ input: Operations.patchCanvas.Input) async throws -> Operations.patchCanvas.Output {
        if case let .json(patch) = input.body {
            core.patchCanvas(gridStep: patch.gridStep, autoScale: patch.autoScale)
        }
        return .ok(.init(body: .json(toSchema(core.getCanvas()))))
    }

    func zoomFit(_ input: Operations.zoomFit.Input) async throws -> Operations.zoomFit.Output {
        core.zoomFit()
        return .noContent
    }

    func zoomActual(_ input: Operations.zoomActual.Input) async throws -> Operations.zoomActual.Output {
        if case let .json(payload)? = input.body {
            core.zoomActual(anchorView: payload.viewPoint.map { CGPoint(x: $0.x, y: $0.y) })
        } else {
            core.zoomActual(anchorView: nil)
        }
        return .noContent
    }

    func zoomSet(_ input: Operations.zoomSet.Input) async throws -> Operations.zoomSet.Output {
        if case let .json(payload) = input.body {
            let anchor = payload.anchorView.map { CGPoint(x: $0.x, y: $0.y) }
            core.zoomSet(scale: payload.scale, anchorView: anchor)
        }
        return .noContent
    }

    func panBy(_ input: Operations.panBy.Input) async throws -> Operations.panBy.Output {
        if case let .json(payload) = input.body {
            core.panBy(dx: payload.dx, dy: payload.dy)
        }
        return .noContent
    }

    // MARK: - Nodes
    func listNodes(_ input: Operations.listNodes.Input) async throws -> Operations.listNodes.Output {
        let arr = core.listNodes().map(toSchema(_:))
        return .ok(.init(body: .json(arr)))
    }

    func createNode(_ input: Operations.createNode.Input) async throws -> Operations.createNode.Output {
        guard case let .json(n) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let created = core.createNode(fromSchema(n))
        return .created(.init(body: .json(toSchema(created))))
    }

    func getNode(_ input: Operations.getNode.Input) async throws -> Operations.getNode.Output {
        let id = input.path.id
        guard let n = core.getNode(id) else { return .undocumented(statusCode: 404, .init()) }
        return .ok(.init(body: .json(toSchema(n))))
    }

    func patchNode(_ input: Operations.patchNode.Input) async throws -> Operations.patchNode.Output {
        let id = input.path.id
        guard case let .json(p) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let updated = core.patchNode(id, title: p.title, x: p.x, y: p.y, w: p.w, h: p.h)
        guard let u = updated else { return .undocumented(statusCode: 404, .init()) }
        return .ok(.init(body: .json(toSchema(u))))
    }

    func deleteNode(_ input: Operations.deleteNode.Input) async throws -> Operations.deleteNode.Output {
        core.deleteNode(input.path.id)
        return .noContent
    }

    func addPort(_ input: Operations.addPort.Input) async throws -> Operations.addPort.Output {
        switch input.body {
        case .json(let port):
            let nodeId = input.path.id
            guard let updated = core.addPort(nodeId: nodeId, port: fromSchema(port)) else { return .undocumented(statusCode: 404, .init()) }
            return .ok(.init(body: .json(toSchema(updated))))
        }
    }

    func removePort(_ input: Operations.removePort.Input) async throws -> Operations.removePort.Output {
        let id = input.path.id
        let portId = input.path.portId
        guard let updated = core.removePort(nodeId: id, portId: portId) else { return .undocumented(statusCode: 404, .init()) }
        return .ok(.init(body: .json(toSchema(updated))))
    }

    // MARK: - Edges
    func listEdges(_ input: Operations.listEdges.Input) async throws -> Operations.listEdges.Output {
        let arr = core.listEdges().map(toSchema(_:))
        return .ok(.init(body: .json(arr)))
    }

    func createEdge(_ input: Operations.createEdge.Input) async throws -> Operations.createEdge.Output {
        guard case let .json(e) = input.body else { return .undocumented(statusCode: 400, .init()) }
        // Generate ID
        let id = UUID().uuidString
        let created = core.createEdge(.init(id: id, from: e.from, to: e.to, routing: toRoutingString(e.routing), width: nil, glow: nil))
        return .created(.init(body: .json(toSchema(created))))
    }

    func deleteEdge(_ input: Operations.deleteEdge.Input) async throws -> Operations.deleteEdge.Output {
        core.deleteEdge(input.path.id)
        return .noContent
    }

    // MARK: - Import/Export
    func exportJSON(_ input: Operations.exportJSON.Input) async throws -> Operations.exportJSON.Output {
        .ok(.init(body: .json(toSchema(core.exportJSON()))))
    }

    func exportDSL(_ input: Operations.exportDSL.Input) async throws -> Operations.exportDSL.Output {
        // Simple, readable DSL to aid debugging
        let doc = core.exportJSON()
        var lines: [String] = []
        lines.append("canvas \(doc.canvas.width)x\(doc.canvas.height) grid=\(doc.canvas.grid) theme=\(doc.canvas.theme)")
        for n in doc.nodes { lines.append("node \(n.id) x=\(n.x) y=\(n.y) w=\(n.w) h=\(n.h) title=\(n.title ?? "")") }
        for e in doc.edges { lines.append("edge \(e.id) from=\(e.from) to=\(e.to) routing=\(e.routing ?? "qcBezier")") }
        let text = lines.joined(separator: "\n")
        return .ok(.init(body: .plainText(OpenAPIRuntime.HTTPBody(stringLiteral: text))))
    }

    func importJSON(_ input: Operations.importJSON.Input) async throws -> Operations.importJSON.Output {
        if case let .json(doc) = input.body { core.importJSON(fromSchema(doc)) }
        return .noContent
    }

    func importDSL(_ input: Operations.importDSL.Input) async throws -> Operations.importDSL.Output {
        // Minimal parser: ignore for now, keep as no-op
        return .noContent
    }

    // MARK: - Mapping helpers
    private func toSchema(_ s: QCMockServiceCore.CanvasState) -> Components.Schemas.CanvasState {
        .init(
            docWidth: s.docWidth,
            docHeight: s.docHeight,
            gridStep: s.gridStep,
            autoScale: s.autoScale,
            transform: .init(
                scale: Double(s.transform.scale),
                translation: .init(x: Double(s.transform.translation.x), y: Double(s.transform.translation.y))
            )
        )
    }

    private func toSchema(_ n: QCMockServiceCore.Node) -> Components.Schemas.Node {
        .init(
            id: n.id,
            title: n.title,
            x: n.x,
            y: n.y,
            w: n.w,
            h: n.h,
            ports: n.ports.map(toSchema(_:))
        )
    }
    private func fromSchema(_ n: Components.Schemas.CreateNode) -> QCMockServiceCore.Node {
        .init(id: n.id, title: n.title, x: n.x, y: n.y, w: n.w, h: n.h, ports: [])
    }
    private func toSchema(_ p: QCMockServiceCore.Port) -> Components.Schemas.Port {
        .init(
            id: p.id,
            side: Components.Schemas.Port.sidePayload(rawValue: p.side) ?? .left,
            dir: Components.Schemas.Port.dirPayload(rawValue: p.dir) ?? ._in,
            _type: Components.Schemas.Port._typePayload(rawValue: p.type) ?? .data
        )
    }
    private func fromSchema(_ p: Components.Schemas.Port) -> QCMockServiceCore.Port {
        .init(id: p.id, side: p.side.rawValue, dir: p.dir.rawValue, type: p._type.rawValue)
    }
    private func toSchema(_ e: QCMockServiceCore.Edge) -> Components.Schemas.Edge {
        .init(id: e.id, from: e.from, to: e.to, routing: toRoutingEnum(e.routing), width: e.width, glow: e.glow)
    }
    private func toRoutingEnum(_ s: String?) -> Components.Schemas.Edge.routingPayload? {
        guard let s else { return nil }
        return .init(rawValue: s)
    }
    private func toRoutingString(_ p: Components.Schemas.CreateEdge.routingPayload?) -> String? {
        p?.rawValue
    }
    private func toSchema(_ d: QCMockServiceCore.GraphDoc) -> Components.Schemas.GraphDoc {
        .init(
            canvas: .init(width: d.canvas.width, height: d.canvas.height, theme: .init(rawValue: d.canvas.theme) ?? .light, grid: d.canvas.grid),
            nodes: d.nodes.map(toSchema(_:)),
            edges: d.edges.map(toSchema(_:))
        )
    }
    private func fromSchema(_ d: Components.Schemas.GraphDoc) -> QCMockServiceCore.GraphDoc {
        let data = try! JSONEncoder().encode(d)
        return try! JSONDecoder().decode(QCMockServiceCore.GraphDoc.self, from: data)
    }
}
