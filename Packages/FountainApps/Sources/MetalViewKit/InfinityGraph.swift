import CoreGraphics

/// InfinityGraph — minimal, UI‑free node/edge model for infinite canvases.
///
/// This core is designed for reuse across hosts (MetalViewKit, SDLKit/Infinity, tests).
/// It owns document‑space graph state only; rendering and UI frameworks sit on top.
public struct InfinityPort: Equatable {
    public enum Side {
        case left, right, top, bottom
    }
    public enum Direction {
        case input
        case output
    }
    public var id: String
    public var side: Side
    public var direction: Direction
    public var type: String

    public init(id: String, side: Side, direction: Direction, type: String = "data") {
        self.id = id
        self.side = side
        self.direction = direction
        self.type = type
    }
}

public struct InfinityNode: Equatable {
    public var id: String
    public var title: String
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var ports: [InfinityPort]

    public init(id: String,
                title: String,
                x: Int,
                y: Int,
                width: Int,
                height: Int,
                ports: [InfinityPort] = []) {
        self.id = id
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.ports = ports
    }

    public var frame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

public struct InfinityEdge: Equatable {
    public var fromNodeId: String
    public var fromPortId: String
    public var toNodeId: String
    public var toPortId: String

    public init(fromNodeId: String, fromPortId: String, toNodeId: String, toPortId: String) {
        self.fromNodeId = fromNodeId
        self.fromPortId = fromPortId
        self.toNodeId = toNodeId
        self.toPortId = toPortId
    }
}

/// Scene‑level graph state for an infinite canvas.
public struct InfinityScene {
    public var nodes: [InfinityNode] = []
    public var edges: [InfinityEdge] = []
    public var grid: Int = 24
    public var selection: Set<String> = []

    public init() {}

    public func nodeIndex(id: String) -> Int? {
        nodes.firstIndex { $0.id == id }
    }

    public func node(id: String) -> InfinityNode? {
        nodes.first { $0.id == id }
    }

    public func portPosition(node: InfinityNode, port: InfinityPort) -> CGPoint {
        let rect = node.frame
        switch port.side {
        case .left:   return CGPoint(x: rect.minX, y: rect.midY)
        case .right:  return CGPoint(x: rect.maxX, y: rect.midY)
        case .top:    return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        }
    }

    /// Return a copy of the scene with a new node appended near the given point, snapped to the grid.
    public func addingNode(at point: CGPoint, baseTitle: String = "Node") -> InfinityScene {
        var copy = self
        let g = max(grid, 1)
        func snap(_ v: CGFloat) -> Int {
            let step = CGFloat(g)
            return Int((v / step).rounded() * step)
        }
        let id = copy.uniqueNodeID(prefix: baseTitle)
        let node = InfinityNode(
            id: id,
            title: baseTitle,
            x: snap(point.x),
            y: snap(point.y),
            width: g * 10,
            height: g * 6,
            ports: []
        )
        copy.nodes.append(node)
        copy.selection = [id]
        return copy
    }

    /// Return a copy of the scene with the given node moved by a document‑space delta.
    public func movingNode(id: String, by delta: CGPoint) -> InfinityScene {
        guard let idx = nodeIndex(id: id) else { return self }
        var copy = self
        var n = copy.nodes[idx]
        n.x += Int(delta.x.rounded())
        n.y += Int(delta.y.rounded())
        copy.nodes[idx] = n
        return copy
    }

    /// Return a copy of the scene with an edge ensured between the given endpoints.
    public func ensuringEdge(from: (String, String), to: (String, String)) -> InfinityScene {
        let fromNodeId = from.0, fromPortId = from.1
        let toNodeId = to.0, toPortId = to.1
        if edges.contains(where: {
            $0.fromNodeId == fromNodeId && $0.fromPortId == fromPortId &&
            $0.toNodeId == toNodeId && $0.toPortId == toPortId
        }) {
            return self
        }
        var copy = self
        copy.edges.append(InfinityEdge(fromNodeId: fromNodeId, fromPortId: fromPortId, toNodeId: toNodeId, toPortId: toPortId))
        return copy
    }

    private func uniqueNodeID(prefix: String) -> String {
        var idx = nodes.count + 1
        var candidate: String
        repeat {
            candidate = "\(prefix)_\(idx)"
            idx += 1
        } while nodes.contains(where: { $0.id == candidate })
        return candidate
    }
}

