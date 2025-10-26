import SwiftUI
import AppKit

enum PBPortSide: String, CaseIterable { case left, right, top, bottom }
enum PBPortDir: String, CaseIterable { case input = "in", output = "out" }

struct PBPort: Identifiable, Hashable {
    var id: String
    var side: PBPortSide
    var dir: PBPortDir
    var type: String = "data"
}

struct PBNode: Identifiable, Hashable {
    var id: String
    var title: String?
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var ports: [PBPort] = []
}

struct PBEdge: Identifiable, Hashable {
    var id: String { from+"→"+to }
    var from: String // nodeId.portId
    var to: String   // nodeId.portId
    var width: Double = 2.0
    var glow: Bool = false
}

@MainActor
final class EditorVM: ObservableObject {
    @Published var nodes: [PBNode] = []
    @Published var edges: [PBEdge] = []
    @Published var selection: String? = nil
    @Published var selected: Set<String> = []
    @Published var zoom: CGFloat = 1.0
    @Published var grid: Int = 24
    @Published var connectMode: Bool = false
    @Published var pendingFrom: (node: String, port: String)? = nil
    @Published var translation: CGPoint = .zero

    func nodeIndex(by id: String) -> Int? { nodes.firstIndex{ $0.id == id } }
    func node(by id: String) -> PBNode? { nodes.first{ $0.id == id } }

    func portPosition(node n: PBNode, port p: PBPort) -> CGPoint {
        let x = CGFloat(n.x), y = CGFloat(n.y), w = CGFloat(n.w), h = CGFloat(n.h)
        switch p.side {
        case .left:   return CGPoint(x: x, y: y + h*0.5)
        case .right:  return CGPoint(x: x + w, y: y + h*0.5)
        case .top:    return CGPoint(x: x + w*0.5, y: y)
        case .bottom: return CGPoint(x: x + w*0.5, y: y + h)
        }
    }

    func addNode(at pt: CGPoint) {
        let g = max(4, grid)
        let snap: (CGFloat)->Int = { Int((($0 / CGFloat(g)).rounded()) * CGFloat(g)) }
        let nid = uniqueNodeID(prefix: "Node")
        let node = PBNode(id: nid, title: nid, x: snap(pt.x), y: snap(pt.y), w: g*10, h: g*6, ports: [])
        nodes.append(node)
        selection = nid
    }

    func addPort(to nodeID: String, side: PBPortSide, dir: PBPortDir, id: String, type: String = "data") {
        guard let idx = nodeIndex(by: nodeID) else { return }
        if nodes[idx].ports.contains(where: { $0.id == id }) { return }
        nodes[idx].ports.append(.init(id: id, side: side, dir: dir, type: type))
    }

    func addEdge(from: (String,String), to: (String,String)) {
        edges.append(.init(from: "\(from.0).\(from.1)", to: "\(to.0).\(to.1)"))
    }

    func removeIncomingEdge(to nodeId: String, portId: String) {
        edges.removeAll { $0.to == "\(nodeId).\(portId)" }
    }

    func tapPort(nodeId: String, portId: String, dir: PBPortDir, optionFanout: Bool) {
        guard connectMode else { return }
        if pendingFrom == nil {
            if dir == .output { pendingFrom = (nodeId, portId) }
            return
        }
        guard let start = pendingFrom else { return }
        if dir == .input {
            if !optionFanout { removeIncomingEdge(to: nodeId, portId: portId) }
            addEdge(from: start, to: (nodeId, portId))
            if !optionFanout { pendingFrom = nil }
        } else {
            pendingFrom = (nodeId, portId)
        }
    }

    func breakConnection(at nodeId: String, portId: String) { removeIncomingEdge(to: nodeId, portId: portId) }

    func uniqueNodeID(prefix: String) -> String {
        var idx = nodes.count + 1
        var candidate: String
        repeat { candidate = "\(prefix)_\(idx)"; idx += 1 } while nodes.contains{ $0.id == candidate }
        return candidate
    }

    func nudgeSelected(dx: Int, dy: Int, step: Int? = nil) {
        let g = step ?? max(1, grid)
        guard !selected.isEmpty else { return }
        for i in 0..<nodes.count {
            if selected.contains(nodes[i].id) {
                nodes[i].x += dx * g
                nodes[i].y += dy * g
            }
        }
    }

    // Logic helpers for tests
    static func gridVisibility(scale: CGFloat, grid: Int) -> (showMinor: Bool, showLabels: Bool) {
        let minor = CGFloat(grid) * max(scale, 0.0001)
        let major = minor * 5.0
        return (minor >= 8.0, major >= 12.0)
    }

    // Compute content bounds in doc units with margin; if empty, return a default square
    func contentBounds(margin: CGFloat = 40) -> CGRect {
        guard !nodes.isEmpty else {
            let s = CGFloat(grid * 20)
            return CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: -margin, dy: -margin)
        }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNormalMagnitude
        var maxY = CGFloat.leastNormalMagnitude
        for n in nodes {
            minX = min(minX, CGFloat(n.x))
            minY = min(minY, CGFloat(n.y))
            maxX = max(maxX, CGFloat(n.x + n.w))
            maxY = max(maxY, CGFloat(n.y + n.h))
        }
        var rect = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        rect = rect.insetBy(dx: -margin, dy: -margin)
        return rect
    }

    static func computeFitZoom(viewSize: CGSize, contentBounds: CGRect, minZoom: CGFloat = 0.25, maxZoom: CGFloat = 3.0) -> CGFloat {
        let sx = viewSize.width / max(1, contentBounds.width)
        let sy = viewSize.height / max(1, contentBounds.height)
        return max(minZoom, min(maxZoom, min(sx, sy)))
    }
}

struct GridBackground: View {
    var size: CGSize; var grid: CGFloat; var scale: CGFloat
    var body: some View {
        Canvas { ctx, sz in
            let W = size.width, H = size.height
            let g1 = Color(NSColor.quaternaryLabelColor)
            let g5 = Color(NSColor.tertiaryLabelColor)
            let minorStepView = grid * max(scale, 0.0001)
            let majorStepView = minorStepView * 5.0
            let showMinor = minorStepView >= 8.0
            let showLabels = majorStepView >= 12.0
            let lw = max(0.5, 1.0 / max(scale, 0.0001))

            var x: CGFloat = 0; var i = 0
            while x <= W {
                let isMajor = (i % 5) == 0
                if isMajor {
                    var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: H))
                    ctx.stroke(path, with: .color(g5), lineWidth: lw)
                    if showLabels { let text = Text("\(i)").font(.system(size: 8)); ctx.draw(text, at: CGPoint(x: x+2, y: 8)) }
                } else if showMinor {
                    var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: H))
                    ctx.stroke(path, with: .color(g1), lineWidth: lw)
                }
                x += minorStepView; i += 1
            }
            var y: CGFloat = 0; i = 0
            while y <= H {
                let isMajor = (i % 5) == 0
                if isMajor {
                    var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: W, y: y))
                    ctx.stroke(path, with: .color(g5), lineWidth: lw)
                } else if showMinor {
                    var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: W, y: y))
                    ctx.stroke(path, with: .color(g1), lineWidth: lw)
                }
                y += minorStepView; i += 1
            }
        }
    }
}

struct BezierEdgeView: View {
    var edge: PBEdge
    var toDoc: (CGPoint) -> CGPoint
    @EnvironmentObject var vm: EditorVM
    var body: some View {
        Path { p in
            guard let (n1,p1) = lookup(edge.from), let (n2,p2) = lookup(edge.to) else { return }
            var a = vm.portPosition(node: n1, port: p1)
            var b = vm.portPosition(node: n2, port: p2)
            a = toDoc(a); b = toDoc(b)
            let radius: CGFloat = 80
            let c1: CGPoint; let c2: CGPoint
            switch p1.side {
            case .left:   c1 = CGPoint(x: a.x - radius, y: a.y); c2 = CGPoint(x: b.x + radius, y: b.y)
            case .right:  c1 = CGPoint(x: a.x + radius, y: a.y); c2 = CGPoint(x: b.x - radius, y: b.y)
            case .top:    c1 = CGPoint(x: a.x, y: a.y - radius); c2 = CGPoint(x: b.x, y: b.y + radius)
            case .bottom: c1 = CGPoint(x: a.x, y: a.y + radius); c2 = CGPoint(x: b.x, y: b.y - radius)
            }
            p.move(to: a)
            p.addCurve(to: b, control1: c1, control2: c2)
        }
        .stroke(Color.accentColor.opacity(edge.glow ? 0.5 : 1.0), lineWidth: CGFloat(edge.width))
    }
    func lookup(_ ref: String) -> (PBNode, PBPort)? {
        let parts = ref.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let n = vm.node(by: parts[0]), let p = n.ports.first(where: { $0.id == parts[1] }) else { return nil }
        return (n, p)
    }
}

struct EditorCanvas: View {
    @EnvironmentObject var vm: EditorVM
    @State private var dragStart: CGPoint? = nil
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeRect: CGRect? = nil

    var body: some View {
        GeometryReader { geo in
            // Keep a square artboard so grid squares remain visually consistent at any pane size
            let side = floor(min(geo.size.width, geo.size.height))
            let docSize = CGSize(width: side, height: side)
            let padX = (geo.size.width - docSize.width) * 0.5
            let padY = (geo.size.height - docSize.height) * 0.5
            let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
            let toView: (CGPoint)->CGPoint = { p in
                let v = transform.docToView(p)
                return CGPoint(x: v.x + padX, y: v.y + padY)
            }
            // Convert view point to document point, accounting for padding offsets
            let toDoc: (CGPoint)->CGPoint = { p in
                let adjusted = CGPoint(x: p.x - padX, y: p.y - padY)
                return transform.viewToDoc(adjusted)
            }

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    GridBackground(size: docSize, grid: CGFloat(vm.grid), scale: vm.zoom)
                    ForEach(vm.edges) { e in BezierEdgeView(edge: e, toDoc: toView).environmentObject(vm) }
                    ForEach(vm.nodes) { n in
                    let rect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(vm.selected.contains(n.id) ? Color.accentColor : Color.secondary, lineWidth: vm.selected.contains(n.id) ? 2 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor))
                        )
                        .overlay(alignment: .topLeading) {
                            Text(n.title ?? n.id).font(.system(size: 11)).padding(4)
                        }
                        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                        .position(x: toView(rect.origin).x + rect.width/2, y: toView(rect.origin).y + rect.height/2)
                        .highPriorityGesture(nodeDragGesture(node: n))
                        .onTapGesture {
                            #if canImport(AppKit)
                            let flags = NSApp.currentEvent?.modifierFlags ?? []
                            if flags.contains(.command) {
                                if vm.selected.contains(n.id) { vm.selected.remove(n.id) } else { vm.selected.insert(n.id) }
                            } else {
                                vm.selected = [n.id]
                            }
                            vm.selection = n.id
                            #else
                            vm.selected = [n.id]
                            vm.selection = n.id
                            #endif
                        }

                        ForEach(n.ports) { p in
                            let center = vm.portPosition(node: n, port: p)
                            let v = toView(center)
                            let color: Color = {
                                guard vm.connectMode, let start = vm.pendingFrom else { return Color.accentColor }
                                if p.dir == .input && start.node != n.id {
                                    if let sNode = vm.node(by: start.node), let sPort = sNode.ports.first(where: { $0.id == start.port }) {
                                        return (sPort.dir == .output && sPort.type == p.type) ? Color.green : Color.red.opacity(0.6)
                                    }
                                }
                                return Color.accentColor
                            }()
                            Circle().fill(color)
                                .frame(width: 6, height: 6)
                                .position(x: v.x, y: v.y)
                                .onTapGesture {
                                    let flags = NSApp.currentEvent?.modifierFlags ?? []
                                    let opt = flags.contains(.option)
                                    vm.tapPort(nodeId: n.id, portId: p.id, dir: p.dir, optionFanout: opt)
                                }
                                .onTapGesture(count: 2) {
                                    if p.dir == .input { vm.breakConnection(at: n.id, portId: p.id) }
                                }
                        }
                    }
                }
                .frame(width: docSize.width, height: docSize.height, alignment: .topLeading)
                .offset(x: padX, y: padY)
                if let rect = marqueeRect {
                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4,3]))
                        .background(Rectangle().fill(Color.accentColor.opacity(0.1)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { v in
                    if marqueeStart == nil { marqueeStart = v.startLocation }
                    let start = marqueeStart ?? v.startLocation
                    let p0 = v.location
                    let x0 = min(start.x, p0.x), y0 = min(start.y, p0.y)
                    let w = abs(start.x - p0.x), h = abs(start.y - p0.y)
                    marqueeRect = CGRect(x: x0, y: y0, width: w, height: h)
                }
                .onEnded { _ in
                    defer { marqueeStart = nil; marqueeRect = nil }
                    guard let rect = marqueeRect, rect.width > 1, rect.height > 1 else { return }
                    var sel: Set<String> = []
                    for n in vm.nodes {
                        let origin = toView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
                        let r = CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w), height: CGFloat(n.h))
                        if r.intersects(rect) { sel.insert(n.id) }
                    }
                    if !sel.isEmpty { vm.selected = sel; vm.selection = sel.first }
                }
            )
            .onReceive(NotificationCenter.default.publisher(for: .pbZoomFit)) { _ in
                let viewSize = geo.size
                let content = vm.contentBounds(margin: 40)
                let z = EditorVM.computeFitZoom(viewSize: viewSize, contentBounds: content)
                let targetX = (viewSize.width - z * content.width) / 2.0
                let targetY = (viewSize.height - z * content.height) / 2.0
                vm.translation = CGPoint(x: targetX / max(0.0001, z) - content.minX,
                                         y: targetY / max(0.0001, z) - content.minY)
                vm.zoom = z
            }
            .onReceive(NotificationCenter.default.publisher(for: .pbZoomActual)) { _ in
                vm.zoom = 1.0
                vm.translation = .zero
            }
            .onReceive(NotificationCenter.default.publisher(for: .pbDelete)) { _ in
                if !vm.selected.isEmpty {
                    let ids = vm.selected
                    vm.nodes.removeAll { ids.contains($0.id) }
                    vm.edges.removeAll { edge in ids.contains(edge.from.split(separator: ".").first.map(String.init) ?? "") || ids.contains(edge.to.split(separator: ".").first.map(String.init) ?? "") }
                    vm.selection = nil
                    vm.selected.removeAll()
                } else if let sel = vm.selection {
                    vm.nodes.removeAll { $0.id == sel }
                    vm.edges.removeAll { $0.from.hasPrefix(sel+".") || $0.to.hasPrefix(sel+".") }
                    vm.selection = nil
                }
            }
        }
    }

    func nodeDragGesture(node: PBNode) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                guard let idx = vm.nodeIndex(by: node.id) else { return }
                if dragStart == nil { dragStart = CGPoint(x: node.x, y: node.y) }
                let start = dragStart ?? CGPoint(x: node.x, y: node.y)
                let dx = v.translation.width / max(0.0001, vm.zoom)
                let dy = v.translation.height / max(0.0001, vm.zoom)
                let nowX = CGFloat(start.x) + dx
                let nowY = CGFloat(start.y) + dy
                vm.nodes[idx].x = Int(nowX)
                vm.nodes[idx].y = Int(nowY)
            }
            .onEnded { _ in
                guard let idx = vm.nodeIndex(by: node.id) else { dragStart = nil; return }
                let g = CGFloat(max(4, vm.grid))
                let x = CGFloat(vm.nodes[idx].x)
                let y = CGFloat(vm.nodes[idx].y)
                vm.nodes[idx].x = Int((round(x / g) * g))
                vm.nodes[idx].y = Int((round(y / g) * g))
                dragStart = nil
            }
    }
}
