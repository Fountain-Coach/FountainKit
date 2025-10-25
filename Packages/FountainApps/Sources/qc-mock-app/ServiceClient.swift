import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

// Thin wrapper over the generated OpenAPI client inside this target.
@MainActor
final class QCMClient {
    private let client: Client
    private let transport: URLSessionTransport
    private let serverURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:7088")!) {
        self.serverURL = baseURL
        self.transport = URLSessionTransport()
        self.client = Client(serverURL: baseURL, transport: transport)
    }

    // Canvas
    func getCanvas() async throws -> Components.Schemas.CanvasState? {
        switch try await client.getCanvas(.init()) {
        case .ok(let ok):
            return try ok.body.json
        default:
            return nil
        }
    }
    func patchCanvas(gridStep: Int? = nil, autoScale: Bool? = nil) async throws -> Components.Schemas.CanvasState? {
        let payload = Components.Schemas.CanvasPatch(gridStep: gridStep, autoScale: autoScale)
        switch try await client.patchCanvas(.init(body: .json(payload))) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
    func zoomSet(scale: Double, anchor: Components.Schemas.Point? = nil) async throws {
        let payload = Operations.zoomSet.Input.Body.jsonPayload(scale: scale, anchorView: anchor)
        _ = try await client.zoomSet(.init(body: .json(payload)))
    }
    func panBy(dx: Double, dy: Double) async throws {
        let payload = Operations.panBy.Input.Body.jsonPayload(dx: dx, dy: dy)
        _ = try await client.panBy(.init(body: .json(payload)))
    }

    // Nodes
    func createNode(id: String, title: String?, x: Int, y: Int, w: Int, h: Int) async throws -> Components.Schemas.Node? {
        let body = Components.Schemas.CreateNode(id: id, title: title, x: x, y: y, w: w, h: h, ports: [])
        switch try await client.createNode(.init(body: .json(body))) {
        case .created(let c): return try c.body.json
        default: return nil
        }
    }
    func addPort(nodeId: String, port: Components.Schemas.Port) async throws -> Components.Schemas.Node? {
        switch try await client.addPort(.init(path: .init(id: nodeId), headers: .init(), body: .json(port))) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
    func createEdge(from: String, to: String, routing: Components.Schemas.CreateEdge.routingPayload = .qcBezier) async throws -> Components.Schemas.Edge? {
        let body = Components.Schemas.CreateEdge(from: from, to: to, routing: routing)
        switch try await client.createEdge(.init(body: .json(body))) {
        case .created(let c): return try c.body.json
        default: return nil
        }
    }
    func exportJSON() async throws -> Components.Schemas.GraphDoc? {
        switch try await client.exportJSON(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
}

// Simple mapping from service GraphDoc -> app QCDocument
extension QCDocument {
    static func from(_ g: Components.Schemas.GraphDoc) -> QCDocument {
        var d = QCDocument()
        d.canvas.width = g.canvas.width
        d.canvas.height = g.canvas.height
        d.canvas.theme = g.canvas.theme.rawValue
        d.canvas.grid = g.canvas.grid
        d.nodes = g.nodes.map { n in
            let ports = n.ports.map { p in
                QCDocument.Port(id: p.id,
                                side: QCDocument.Side(rawValue: p.side.rawValue) ?? .left,
                                dir: (p.dir.rawValue == "in" ? .input : .output),
                                type: p._type.rawValue)
            }
            return QCDocument.Node(id: n.id, title: n.title, x: n.x, y: n.y, w: n.w, h: n.h, ports: ports)
        }
        d.edges = g.edges.map { e in
            QCDocument.Edge(from: e.from, to: e.to, routing: e.routing?.rawValue, width: e.width, glow: e.glow)
        }
        return d
    }
}
