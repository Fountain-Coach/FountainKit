import Foundation
import CoreGraphics
import QCMockCore

public struct CanvasState: Equatable {
    public var docWidth: Int
    public var docHeight: Int
    public var gridStep: Int
    public var autoScale: Bool
    public var transform: CanvasTransform
    public init(docWidth: Int, docHeight: Int, gridStep: Int, autoScale: Bool = true, transform: CanvasTransform = .init()) {
        self.docWidth = docWidth; self.docHeight = docHeight; self.gridStep = gridStep; self.autoScale = autoScale; self.transform = transform
    }
}

public struct Port: Codable, Equatable { public var id: String; public var side: String; public var dir: String; public var type: String; public init(id: String, side: String, dir: String, type: String) { self.id = id; self.side = side; self.dir = dir; self.type = type } }
public struct Node: Codable, Equatable { public var id: String; public var title: String?; public var x: Int; public var y: Int; public var w: Int; public var h: Int; public var ports: [Port]; public init(id: String, title: String?, x: Int, y: Int, w: Int, h: Int, ports: [Port]) { self.id = id; self.title = title; self.x = x; self.y = y; self.w = w; self.h = h; self.ports = ports } }
public struct Edge: Codable, Equatable { public var id: String; public var from: String; public var to: String; public var routing: String?; public var width: Double?; public var glow: Bool?; public init(id: String, from: String, to: String, routing: String?, width: Double?, glow: Bool?) { self.id = id; self.from = from; self.to = to; self.routing = routing; self.width = width; self.glow = glow } }

public struct GraphDoc: Codable, Equatable { public var canvas: CanvasDoc; public var nodes: [Node]; public var edges: [Edge] }
public struct CanvasDoc: Codable, Equatable { public var width: Int; public var height: Int; public var theme: String; public var grid: Int }

public final class ServiceCore {
    public private(set) var canvas: CanvasState
    public private(set) var nodes: [String: Node] = [:]
    public private(set) var edges: [String: Edge] = [:]
    public init(docWidth: Int = 1200, docHeight: Int = 800, gridStep: Int = 24) {
        self.canvas = CanvasState(docWidth: docWidth, docHeight: docHeight, gridStep: gridStep, autoScale: true, transform: .init())
    }
    // Canvas ops
    public func getCanvas() -> CanvasState { canvas }
    public func patchCanvas(gridStep: Int? = nil, autoScale: Bool? = nil) { if let g = gridStep { canvas.gridStep = max(1, g) }; if let a = autoScale { canvas.autoScale = a } }
    public func zoomFit() { canvas.transform.scale = 1.0; canvas.transform.translation = .zero }
    public func zoomActual(anchorView: CGPoint? = nil) { if let a = anchorView { canvas.transform.zoom(around: a, factor: 1.0/canvas.transform.scale) } else { canvas.transform.scale = 1.0; canvas.transform.translation = .zero } }
    public func zoomSet(scale: CGFloat, anchorView: CGPoint?) { let s = max(0.1, min(16.0, scale)); if let a = anchorView { let factor = s / max(0.0001, canvas.transform.scale); canvas.transform.zoom(around: a, factor: factor, min: 0.1, max: 16.0) } else { canvas.transform.scale = s } }
    public func panBy(dx: CGFloat, dy: CGFloat) { canvas.transform.translation.x += dx; canvas.transform.translation.y += dy }

    // Node ops
    public func listNodes() -> [Node] { Array(nodes.values) }
    public func createNode(_ n: Node) -> Node { nodes[n.id] = n; return n }
    public func getNode(_ id: String) -> Node? { nodes[id] }
    public func patchNode(_ id: String, title: String? = nil, x: Int? = nil, y: Int? = nil, w: Int? = nil, h: Int? = nil) -> Node? {
        guard var n = nodes[id] else { return nil }
        if let t = title { n.title = t }
        if let v = x { n.x = v }
        if let v = y { n.y = v }
        if let v = w { n.w = v }
        if let v = h { n.h = v }
        nodes[id] = n; return n
    }
    public func deleteNode(_ id: String) { nodes.removeValue(forKey: id) }
    public func addPort(nodeId: String, port: Port) -> Node? { guard var n = nodes[nodeId] else { return nil }; n.ports.append(port); nodes[nodeId] = n; return n }
    public func removePort(nodeId: String, portId: String) -> Node? { guard var n = nodes[nodeId] else { return nil }; n.ports.removeAll{ $0.id == portId }; nodes[nodeId] = n; return n }

    // Edge ops
    public func listEdges() -> [Edge] { Array(edges.values) }
    public func createEdge(_ e: Edge) -> Edge { edges[e.id] = e; return e }
    public func deleteEdge(_ id: String) { edges.removeValue(forKey: id) }

    // Import/Export
    public func exportJSON() -> GraphDoc {
        GraphDoc(canvas: .init(width: canvas.docWidth, height: canvas.docHeight, theme: "light", grid: canvas.gridStep), nodes: listNodes(), edges: listEdges())
    }
    public func importJSON(_ doc: GraphDoc) { canvas.docWidth = doc.canvas.width; canvas.docHeight = doc.canvas.height; canvas.gridStep = doc.canvas.grid; nodes = Dictionary(uniqueKeysWithValues: doc.nodes.map{ ($0.id, $0) }); edges = Dictionary(uniqueKeysWithValues: doc.edges.map{ ($0.id, $0) }) }
}
