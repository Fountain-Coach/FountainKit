import SwiftUI
import AppKit
import Foundation

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
    @Published var pageSize: CGSize = PageSpec.a4Portrait
    @Published var marginMM: CGFloat = 12.0
    @Published var gridMinorMM: CGFloat = 5.0
    @Published var gridMajorMM: CGFloat = 10.0

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

    // Ensure an edge exists; return true if newly added
    @discardableResult
    func ensureEdge(from: (String,String), to: (String,String)) -> Bool {
        let f = "\(from.0).\(from.1)"
        let t = "\(to.0).\(to.1)"
        if edges.contains(where: { $0.from == f && $0.to == t }) { return false }
        edges.append(.init(from: f, to: t))
        return true
    }

    func setGlow(fromRef: String, toRef: String, glow: Bool) {
        for i in 0..<edges.count {
            if edges[i].from == fromRef && edges[i].to == toRef {
                edges[i].glow = glow
            }
        }
    }

    func transientGlowEdge(fromRef: String, toRef: String, duration: TimeInterval = 1.5) {
        setGlow(fromRef: fromRef, toRef: toRef, glow: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.setGlow(fromRef: fromRef, toRef: toRef, glow: false)
        }
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

    // MARK: - GraphDoc mapping
    func toGraphDoc(with instruments: [Components.Schemas.Instrument]) -> Components.Schemas.GraphDoc {
        let content = contentBounds(margin: 40)
        let canvas = Components.Schemas.GraphDoc.canvasPayload(width: Int(max(1, content.width)), height: Int(max(1, content.height)), theme: .light, grid: grid)
        // Map instruments by id if a node with same id exists; otherwise include instrument as-is
        let instById = Dictionary(uniqueKeysWithValues: instruments.map { ($0.id, $0) })
        var mapped: [Components.Schemas.Instrument] = []
        for n in nodes {
            if var i = instById[n.id] {
                i.x = n.x; i.y = n.y; i.w = n.w; i.h = n.h
                mapped.append(i)
            }
        }
        // Add any instruments not on canvas
        for (id, i) in instById where !nodes.contains(where: { $0.id == id }) {
            mapped.append(i)
        }
        // Map edges to property links
        let links: [Components.Schemas.Link] = edges.enumerated().map { idx, e in
            let prop = Components.Schemas.PropertyLink(from: e.from, to: e.to, direction: .a_to_b)
            return Components.Schemas.Link(id: "edge-\(idx)", kind: .property, property: prop, ump: nil)
        }
        return Components.Schemas.GraphDoc(canvas: canvas, instruments: mapped, links: links)
    }

    func applyGraphDoc(_ doc: Components.Schemas.GraphDoc) {
        self.grid = doc.canvas.grid
        // Build nodes from instruments
        var newNodes: [PBNode] = []
        for i in doc.instruments {
            let id = i.id
            var ports: [PBPort] = []
            // Default data ports
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
            // UMP ports
            if i.identity.hasUMPInput == true { ports.append(.init(id: "umpIn", side: .left, dir: .input, type: "ump")) }
            if i.identity.hasUMPOutput == true { ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump")) }
            let n = PBNode(id: id, title: i.title, x: i.x, y: i.y, w: i.w, h: i.h, ports: ports)
            newNodes.append(n)
        }
        self.nodes = newNodes
        // Build edges from property links
        var newEdges: [PBEdge] = []
        for l in doc.links {
            if l.kind == .property, let p = l.property {
                newEdges.append(PBEdge(from: p.from ?? "", to: p.to ?? ""))
            }
        }
        self.edges = newEdges
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

    nonisolated static func computeFitZoom(viewSize: CGSize, contentBounds: CGRect, minZoom: CGFloat = 0.25, maxZoom: CGFloat = 3.0) -> CGFloat {
        let sx = viewSize.width / max(1, contentBounds.width)
        let sy = viewSize.height / max(1, contentBounds.height)
        return max(minZoom, min(maxZoom, min(sx, sy)))
    }

    nonisolated static func computeCenterTranslation(viewSize: CGSize, contentBounds: CGRect, zoom: CGFloat) -> CGPoint {
        let z = max(0.0001, zoom)
        let targetX = (viewSize.width - z * contentBounds.width) / 2.0
        let targetY = (viewSize.height - z * contentBounds.height) / 2.0
        return CGPoint(x: targetX / z - contentBounds.minX,
                       y: targetY / z - contentBounds.minY)
    }

    // When the page view is centered in its container via padding (padX/padY),
    // use this translation so the scaled page content is centered within the page frame.
    nonisolated static func computeFrameCenterTranslation(pageSize: CGSize, zoom: CGFloat) -> CGPoint {
        let z = max(0.0001, zoom)
        let tx = (pageSize.width * (1.0 - z)) / (2.0 * z)
        let ty = (pageSize.height * (1.0 - z)) / (2.0 * z)
        return CGPoint(x: tx, y: ty)
    }
}

struct GridBackground: View {
    var size: CGSize
    var minorStepPoints: CGFloat
    var majorStepPoints: CGFloat
    var margin: EdgeInsets // in points
    var scale: CGFloat
    var translation: CGPoint // doc-space translation

    nonisolated static func periodicOffset(_ translation: CGFloat, _ scale: CGFloat, _ stepView: CGFloat) -> CGFloat {
        let raw = translation * scale
        let m = stepView
        if m <= 0 { return 0 }
        var o = raw.truncatingRemainder(dividingBy: m)
        if o < 0 { o += m }
        return o
    }

    var body: some View {
        Canvas { ctx, sz in
            let W = size.width, H = size.height
            let g1 = Color(NSColor.quaternaryLabelColor)
            let g5 = Color(NSColor.tertiaryLabelColor)
            let s = max(scale, 0.0001)
            let minorStepView = minorStepPoints * s
            let majorStepView = majorStepPoints * s
            let showMinor = minorStepView >= 8.0
            let showLabels = majorStepView >= 12.0
            let lw = max(0.5, 1.0 / s)

            // Draw page background
            let pageRect = CGRect(x: 0, y: 0, width: W, height: H)
            ctx.fill(Path(pageRect), with: .color(Color(NSColor.textBackgroundColor)))

            // Grid lines (full page, Y-down) with translation (panning)
            let startX = GridBackground.periodicOffset(translation.x, s, minorStepView)
            let startY = GridBackground.periodicOffset(translation.y, s, minorStepView)
            let majorRatio = max(1, Int(round(majorStepPoints / max(0.0001, minorStepPoints))))
            var x: CGFloat = startX; var i = 0
            while x <= W {
                if (i % majorRatio) == 0 {
                    var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: H))
                    ctx.stroke(path, with: .color(g5), lineWidth: lw)
                    if showLabels { let text = Text("\(i * majorRatio)").font(.system(size: 8)); ctx.draw(text, at: CGPoint(x: x+2, y: 8)) }
                } else if showMinor {
                    var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: H))
                    ctx.stroke(path, with: .color(g1), lineWidth: lw)
                }
                x += minorStepView; i += 1
            }
            var y: CGFloat = startY; i = 0
            while y <= H {
                if (i % majorRatio) == 0 {
                    var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: W, y: y))
                    ctx.stroke(path, with: .color(g5), lineWidth: lw)
                } else if showMinor {
                    var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: W, y: y))
                    ctx.stroke(path, with: .color(g1), lineWidth: lw)
                }
                y += minorStepView; i += 1
            }

            // Margin box (guides)
            let marginRect = CGRect(x: margin.leading, y: margin.top, width: W - margin.leading - margin.trailing, height: H - margin.top - margin.bottom)
            let mpath = Path(roundedRect: marginRect, cornerSize: .zero)
            ctx.stroke(mpath, with: .color(Color(NSColor.systemRed).opacity(0.35)), lineWidth: lw)
        }
    }
}

struct BezierEdgeView: View {
    var edge: PBEdge
    var toDoc: (CGPoint) -> CGPoint
    @EnvironmentObject var vm: EditorVM
    var body: some View {
        let path = buildPath()
        path.stroke(Color.accentColor, lineWidth: CGFloat(edge.width))
            .overlay(
                Group {
                    if edge.glow {
                        buildPath()
                            .stroke(Color.yellow.opacity(0.8), lineWidth: CGFloat(edge.width) + 4)
                            .blur(radius: 0.5)
                    }
                }
            )
    }
    func buildPath() -> Path {
        var p = Path()
        guard let (n1,p1) = lookup(edge.from), let (n2,p2) = lookup(edge.to) else { return p }
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
        return p
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
    @State private var didInitialFit: Bool = false

    var body: some View {
        GeometryReader { geo in
            // Fixed A4 page as the canvas (portrait by default)
            let docSize = vm.pageSize
            let padX = (geo.size.width - docSize.width) * 0.5
            let padY = (geo.size.height - docSize.height) * 0.5
            let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
            let toView: (CGPoint)->CGPoint = { p in
                let v = transform.docToView(p)
                return CGPoint(x: v.x + padX, y: v.y + padY)
            }
            // Convert view point to document point reserved for later features
            // let toDoc: (CGPoint)->CGPoint = { p in
            //     let adjusted = CGPoint(x: p.x - padX, y: p.y - padY)
            //     return transform.viewToDoc(adjusted)
            // }

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    let minor = PageSpec.mm(vm.gridMinorMM)
                    let major = PageSpec.mm(vm.gridMajorMM)
                    let m = EdgeInsets(top: PageSpec.mm(vm.marginMM), leading: PageSpec.mm(vm.marginMM), bottom: PageSpec.mm(vm.marginMM), trailing: PageSpec.mm(vm.marginMM))
                    GridBackground(size: docSize, minorStepPoints: minor, majorStepPoints: major, margin: m, scale: vm.zoom, translation: vm.translation)
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
                // Fit the page to the available view, then center within the page frame
                let viewSize = geo.size
                let content = CGRect(origin: .zero, size: docSize)
                let z = EditorVM.computeFitZoom(viewSize: viewSize, contentBounds: content)
                vm.translation = EditorVM.computeFrameCenterTranslation(pageSize: docSize, zoom: z)
                vm.zoom = z
            }
            .onReceive(NotificationCenter.default.publisher(for: .pbZoomActual)) { _ in
                vm.zoom = 1.0
                vm.translation = .zero
            }
            .onAppear {
                // Ensure initial open is fit-to-page
                if !didInitialFit {
                    let viewSize = geo.size
                    let content = CGRect(origin: .zero, size: docSize)
                    let z = EditorVM.computeFitZoom(viewSize: viewSize, contentBounds: content)
                    vm.translation = EditorVM.computeFrameCenterTranslation(pageSize: docSize, zoom: z)
                    vm.zoom = z
                    didInitialFit = true
                }
            }
            .onChange(of: vm.pageSize) { _,_ in
                let viewSize = geo.size
                let content = CGRect(origin: .zero, size: vm.pageSize)
                let z = EditorVM.computeFitZoom(viewSize: viewSize, contentBounds: content)
                vm.translation = EditorVM.computeFrameCenterTranslation(pageSize: vm.pageSize, zoom: z)
                vm.zoom = z
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
                let g = PageSpec.mm(vm.gridMajorMM)
                let x = CGFloat(vm.nodes[idx].x)
                let y = CGFloat(vm.nodes[idx].y)
                vm.nodes[idx].x = Int((round(x / g) * g))
                vm.nodes[idx].y = Int((round(y / g) * g))
                dragStart = nil
            }
    }
}
