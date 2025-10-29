import SwiftUI
import AppKit
import Flow
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

// Canonical ports sort: inputs -> [in, umpIn, ...]; outputs -> [out, umpOut, ...]
func canonicalSortPorts(_ ports: [PBPort]) -> [PBPort] {
    func rank(_ p: PBPort) -> (Int, String) {
        switch p.dir {
        case .input:
            if p.id == "in" { return (0, "") }
            if p.id == "umpIn" { return (1, "") }
            return (2, p.id)
        case .output:
            if p.id == "out" { return (0, "") }
            if p.id == "umpOut" { return (1, "") }
            return (2, p.id)
        }
    }
    return ports.sorted { a, b in
        let ra = rank(a), rb = rank(b)
        if ra.0 != rb.0 { return ra.0 < rb.0 }
        return ra.1 < rb.1
    }
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
    @Published var lastViewSize: CGSize = .zero
    // Overlays removed in monitor mode (no zones/notes overlays)
    // Grid spacing in points (minor). Major lines are drawn every `majorEvery` minors.
    @Published var majorEvery: Int = 5
    @Published var showPanelsOverlay: Bool = false
    // HUD: baseline index labels for Stage inputs
    @Published var showBaselineIndex: Bool = true
    @Published var alwaysShowBaselineIndex: Bool = false
    @Published var baselineIndexOneBased: Bool = false

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

    // MARK: - Z-order (reordering)
    func bringToFront(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var kept: [PBNode] = []
        var lifted: [PBNode] = []
        for n in nodes { if ids.contains(n.id) { lifted.append(n) } else { kept.append(n) } }
        nodes = kept + lifted
    }
    func sendToBack(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var kept: [PBNode] = []
        var lowered: [PBNode] = []
        for n in nodes { if ids.contains(n.id) { lowered.append(n) } else { kept.append(n) } }
        nodes = lowered + kept
    }

    func setNodeTitle(id: String, title: String) {
        if let i = nodeIndex(by: id) { nodes[i].title = title }
    }

    func reorderStages(orderedStageIds: [String], isStage: (PBNode)->Bool) {
        let stageSet = Set(orderedStageIds)
        var others: [PBNode] = []
        var stagesDict: [String: PBNode] = [:]
        for n in nodes { if isStage(n) { stagesDict[n.id] = n } else { others.append(n) } }
        var reordered: [PBNode] = []
        for sid in orderedStageIds { if let n = stagesDict[sid] { reordered.append(n) } }
        nodes = others + reordered
    }

    func centerOnNode(id: String) {
        guard let n = node(by: id) else { return }
        let view = lastViewSize
        guard view.width > 0 && view.height > 0 else { return }
        let z = max(0.0001, zoom)
        let docCenter = CGPoint(x: CGFloat(n.x + n.w/2), y: CGFloat(n.y + n.h/2))
        let viewCenter = CGPoint(x: view.width/2, y: view.height/2)
        translation = CGPoint(x: viewCenter.x / z - docCenter.x,
                              y: viewCenter.y / z - docCenter.y)
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

            // Background fill
            let rect = CGRect(x: 0, y: 0, width: W, height: H)
            ctx.fill(Path(rect), with: .color(Color(NSColor.textBackgroundColor)))

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

            // No page margins in infinite artboard mode
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

// Transient puff animation when a node is deleted via trash
struct PuffItem: Identifiable { let id = UUID(); var center: CGPoint }
struct PuffView: View {
    var center: CGPoint
    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 0.7
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 20, height: 20)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(center)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) {
                    scale = 1.8
                    opacity = 0.0
                }
            }
    }
}

struct EditorCanvas: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    @State private var dragStart: CGPoint? = nil
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeRect: CGRect? = nil
    @State private var flowPatch: Patch = Patch(nodes: [], wires: [])
    @State private var flowSelection: Set<NodeIndex> = []
    @State private var flowNodeIds: [String] = []
    @State private var flowNodeNames: [String] = []
    private func dynamicTitle(for n: PBNode) -> String {
        if let dash = state.dashboard[n.id] {
            switch dash.kind {
            case .stageA4:
                return dash.props["title"] ?? (n.title ?? n.id)
            case .panelLine, .panelStat, .panelTable:
                let base = dash.props["title"] ?? (n.title ?? n.id)
                // Find upstream provider for quick status text
                let up = vm.edges.first(where: { $0.to == n.id+".in" })?.from.split(separator: ".").first.map(String.init)
                if let up, case .text(let t) = state.dashOutputs[up] ?? .none {
                    let first = t.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? t
                    return base + "\n" + first
                }
                return base
            default:
                return n.title ?? n.id
            }
        }
        return n.title ?? n.id
    }
    private func syncFlowSelectionFromVM() {
        var indexById: [String:Int] = [:]
        for (idx, id) in flowNodeIds.enumerated() { if indexById[id] == nil { indexById[id] = idx } }
        var sel: Set<NodeIndex> = []
        for id in vm.selected { if let idx = indexById[id] { sel.insert(idx) } }
        if let id = vm.selection, let idx = indexById[id] { sel.insert(idx) }
        flowSelection = sel
    }
    @State private var didInitialFit: Bool = false
    @State private var trashRectView: CGRect = .zero
    @State private var trashHover: Bool = false
    @State private var puffItems: [PuffItem] = []
    @StateObject private var exec = DashboardExecutor()

    var body: some View {
        GeometryReader { geo in
            // Infinite artboard: the document matches the visible size; no page padding.
            let docSize = geo.size
            let padX: CGFloat = 0
            let padY: CGFloat = 0
            let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
            let toView: (CGPoint)->CGPoint = { p in
                // Include page-centering padding when in page mode so marquee/select math aligns
                let v = transform.docToView(p)
                return CGPoint(x: v.x + padX, y: v.y + padY)
            }
            // Convert view point to document point reserved for later features
            // let toDoc: (CGPoint)->CGPoint = { p in
            //     let adjusted = CGPoint(x: p.x - padX, y: p.y - padY)
            //     return transform.viewToDoc(adjusted)
            // }

            let mainLayer: AnyView = AnyView(
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    let minor = CGFloat(vm.grid)
                    let major = CGFloat(vm.grid * max(1, vm.majorEvery))
                AnyView(GridBackground(size: docSize, minorStepPoints: minor, majorStepPoints: major, scale: vm.zoom, translation: vm.translation))
                AnyView(flowEditorOverlay(docSize: docSize)
                    .frame(width: docSize.width, height: docSize.height)
                    .overlay(NodeHandleOverlay(docSize: docSize).environmentObject(vm).environmentObject(state))
                    .overlay(BaselineIndexOverlay(docSize: docSize).environmentObject(vm).environmentObject(state)))
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
                // Garbage can (always on): bottom-right, fixed size
                let trashSize: CGFloat = 64
                let trashPadding: CGFloat = 16
                let trashX = geo.size.width - trashPadding - trashSize/2
                let trashY = geo.size.height - trashPadding - trashSize/2
                Color.clear
                    .frame(width: trashSize, height: trashSize)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(trashHover ? Color.red : Color.secondary, lineWidth: trashHover ? 3 : 1)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor).opacity(0.6)))
                            Image(systemName: trashHover ? "trash.fill" : "trash")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundColor(trashHover ? .red : .secondary)
                        }
                    )
                    .position(x: trashX, y: trashY)
                    .help("Drag a node here to delete it")
                    .onAppear { trashRectView = CGRect(x: geo.size.width - trashPadding - trashSize, y: geo.size.height - trashPadding - trashSize, width: trashSize, height: trashSize) }
                    .onChange(of: geo.size) { _, _ in trashRectView = CGRect(x: geo.size.width - trashPadding - trashSize, y: geo.size.height - trashPadding - trashSize, width: trashSize, height: trashSize) }

                // Puff animations overlay
                ForEach(puffItems) { item in PuffView(center: item.center) }
            })
            mainLayer
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .contextMenu { QuickActionsMenu().environmentObject(vm).environmentObject(state) }
            .onChange(of: geo.size) { _, newSize in vm.lastViewSize = newSize }
            .onAppear { vm.lastViewSize = geo.size }
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
                // Infinite artboard: fitting resets zoom to 1 and centers translation.
                vm.translation = .zero
                vm.zoom = 1.0
            }
            .onReceive(NotificationCenter.default.publisher(for: .pbZoomActual)) { _ in
                vm.zoom = 1.0
                vm.translation = .zero
            }
            .onAppear {
                // Initial open: reset to a sensible default for infinite artboard
                if !didInitialFit { vm.translation = .zero; vm.zoom = 1.0; didInitialFit = true }
                flowPatch = FlowBridge.toFlowPatch(vm: vm, titleFor: { $0.title ?? $0.id }, isStage: { n in
                    if let k = state.dashboard[n.id]?.kind { return k == .stageA4 }
                    return false
                })
                flowNodeIds = vm.nodes.map { $0.id }
                syncFlowSelectionFromVM()
                // dashboard exec rebuild disabled (composition-only)
            }
            .onChange(of: vm.nodes) { _, _ in
                // Rebuild flow patch only when structure (IDs) changes; ignore position-only drags to keep NodeEditor stable
                let ids = vm.nodes.map { $0.id }
                let names = vm.nodes.map { $0.title ?? $0.id }
                if ids != flowNodeIds || names != flowNodeNames {
                    flowPatch = FlowBridge.toFlowPatch(vm: vm, titleFor: dynamicTitle, isStage: { n in
                        if let k = state.dashboard[n.id]?.kind { return k == .stageA4 }
                        return false
                    })
                    flowNodeIds = ids
                    flowNodeNames = names
                    syncFlowSelectionFromVM()
                }
                // exec.rebuild(vm: vm, registry: state.dashboard)
            }
            .onChange(of: vm.edges) { _, _ in
                flowPatch = FlowBridge.toFlowPatch(vm: vm, titleFor: dynamicTitle, isStage: { n in
                    if let k = state.dashboard[n.id]?.kind { return k == .stageA4 }
                    return false
                })
                flowNodeIds = vm.nodes.map { $0.id }
                syncFlowSelectionFromVM()
                // exec.rebuild(vm: vm, registry: state.dashboard)
            }
            .background(ExecutorHook())
            // Deletion via keyboard/menu disabled (dustbin-only)
        }
}

fileprivate struct NodeHandleOverlay: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    var docSize: CGSize
    @State private var editingId: String? = nil
    @State private var draft: String = ""
    @FocusState private var nameFocused: Bool
    var body: some View {
        let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
        return ZStack(alignment: .topLeading) {
            ForEach(vm.nodes, id: \.id) { n in
                if let dash = state.dashboard[n.id] {
                    let origin = transform.docToView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
                    let rectView = CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w)*vm.zoom, height: CGFloat(n.h)*vm.zoom)
                    // Stage: page shell inside node (panels omitted here to keep this layer simple and fast)
                    if dash.kind == .stageA4 {
                        let page = dash.props["page"] ?? "A4"
                        let mstr = dash.props["margins"] ?? "18,18,18,18"
                        let bl = CGFloat(Double(dash.props["baseline"] ?? "12") ?? 12)
                        StageView(title: dash.props["title"] ?? (n.title ?? n.id),
                                  page: page,
                                  margins: parseInsetsLocal(mstr),
                                  baseline: bl)
                            .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                            .position(x: rectView.minX, y: rectView.minY)
                            .allowsHitTesting(false)
                    }
                    

                    // Hit area for rename (Stages only)
                    if dash.kind == .stageA4 {
                        Color.clear
                            .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                            .position(x: rectView.minX, y: rectView.minY)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { beginRename(n) }
                            .contextMenu { Button("Rename Stage…") { beginRename(n) } }
                    }
                    if editingId == n.id {
                        // Inline editor anchored near the top of the node box
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                TextField("Stage name", text: $draft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: max(160, rectView.width * 0.6))
                                    .focused($nameFocused)
                                    .onSubmit { commitRename(n.id) }
                                Button("Save") { commitRename(n.id) }
                                Button("Cancel") { editingId = nil }
                            }
                            .padding(6)
                            .background(.regularMaterial)
                            .cornerRadius(8)
                            .shadow(radius: 6)
                        }
                        .position(x: rectView.minX + 12, y: rectView.minY + 18)
                        .onAppear { DispatchQueue.main.async { nameFocused = true } }
                    }
                }
            }
        }
        .allowsHitTesting(true)
    }
    private func beginRename(_ n: PBNode) {
        editingId = n.id
        draft = state.dashboard[n.id]?.props["title"] ?? (n.title ?? n.id)
    }
    private func commitRename(_ id: String) {
        guard var node = state.dashboard[id] else { editingId = nil; return }
        node.props["title"] = draft
        state.updateDashProps(id: id, props: node.props)
        vm.setNodeTitle(id: id, title: draft)
        editingId = nil
    }

    private func parseInsetsLocal(_ s: String) -> EdgeInsets {
        let parts = s.split(separator: ",").compactMap{ Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 4 { return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[3]) }
        return EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    }
}

// HUD overlay: draws small numeric ticks near Stage input ports
fileprivate struct BaselineIndexOverlay: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    var docSize: CGSize
    var body: some View {
        let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
        return ZStack(alignment: .topLeading) {
            if vm.showBaselineIndex {
                ForEach(vm.nodes, id: \.id) { n in
                    if let dash = state.dashboard[n.id], dash.kind == .stageA4 {
                        // Only show when selected, unless always-on
                        if vm.alwaysShowBaselineIndex || vm.selection == n.id {
                            let origin = transform.docToView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
                            let rectView = CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w)*vm.zoom, height: CGFloat(n.h)*vm.zoom)
                            let inPorts = canonicalSortPorts(n.ports.filter { $0.dir == .input && $0.id.hasPrefix("in") })
                            let count = max(0, inPorts.count)
                            if count > 0 {
                                ForEach(Array(inPorts.enumerated()), id: \.element.id) { idx, _ in
                                    let k = vm.baselineIndexOneBased ? (idx + 1) : idx
                                    // Evenly distribute indices along the node height (match port placement)
                                    let frac = CGFloat(idx + 1) / CGFloat(count + 1)
                                    let y = rectView.minY + rectView.height * frac
                                    // Place label just inside the left edge
                                    let x = rectView.minX + 6
                                    Text("\(k)")
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 0)
                                        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .position(x: x, y: y)
                                        .allowsHitTesting(false)
                                        .accessibilityLabel(Text("Stage \(dash.props["title"] ?? (n.title ?? n.id)), input \(k) of \(count)"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fileprivate struct ExecutorHook: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    @StateObject private var exec = DashboardExecutor()
    var body: some View {
        Color.clear
            .onChange(of: state.dashboard.count) { _, _ in exec.rebuild(vm: vm, registry: state.dashboard) }
            .task {
                exec.rebuild(vm: vm, registry: state.dashboard)
                while true {
                    await exec.tick()
                    await MainActor.run { state.dashOutputs = exec.outputs }
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
    }

    private func lastId(where pred: (String, DashKind) -> Bool) -> String? {
        let ids = vm.nodes.map { $0.id }
        for id in ids.reversed() { if let k = state.dashboard[id]?.kind, pred(id, k) { return id } }
        return nil
    }
    private func connectFromLastDatasource(into id: String) {
        if let ds = lastId(where: { _, k in k == .datasource }) { _ = vm.ensureEdge(from: (ds,"out"), to: (id,"in")) }
    }
    private func connectFromLastSeriesNode(into id: String) {
        if let up = lastId(where: { _, k in k == .transform || k == .query || k == .aggregator || k == .topN || k == .threshold }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in")) }
    }
    private func connectOverlayFromLastThreshold(into id: String) {
        if let thr = lastId(where: { _, k in k == .threshold }) { _ = vm.ensureEdge(from: (thr,"out"), to: (id,"overlayIn")) }
    }
    private func connectFromLastAggregator(into id: String) {
        if let agg = lastId(where: { _, k in k == .aggregator }) { _ = vm.ensureEdge(from: (agg,"out"), to: (id,"in")) }
    }
    private func connectFromLastTopN(into id: String) {
        if let top = lastId(where: { _, k in k == .topN }) { _ = vm.ensureEdge(from: (top,"out"), to: (id,"in")) }
    }
    private func connectIntoStage(into id: String) {
        if let up = lastId(where: { _, k in k == .panelLine || k == .panelStat || k == .panelTable }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in0")) }
    }
}

fileprivate struct PanelsOverlayHost: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    var docSize: CGSize
    var body: some View {
        let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
        return ZStack(alignment: .topLeading) {
            ForEach(vm.nodes, id: \.id) { n in
                if let dash = state.dashboard[n.id] {
                    let origin = transform.docToView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
                    let rectView = CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w)*vm.zoom, height: CGFloat(n.h)*vm.zoom)
                    switch dash.kind {
                    case .panelLine:
                        let upstream = vm.edges.first(where: { $0.to == n.id+".in" })?.from.split(separator: ".").first.map(String.init)
                        let sPayload = upstream.flatMap { state.dashOutputs[$0] } ?? .none
                        Group {
                            if case .timeSeries(let series) = sPayload {
                                LineOverlayPanelView(title: dash.props["title"] ?? (n.title ?? n.id), series: series, annotations: [])
                            } else if case .text(let t) = sPayload {
                                VStack(alignment: .leading) { Text(dash.props["title"] ?? (n.title ?? n.id)).font(.caption); Text(t).font(.caption2) }
                            } else {
                                VStack(alignment: .leading) { Text(dash.props["title"] ?? (n.title ?? n.id)).font(.caption); Text("No data").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                        .position(x: rectView.minX, y: rectView.minY)
                        .allowsHitTesting(false)
                    case .panelStat:
                        let upstream = vm.edges.first(where: { $0.to == n.id+".in" })?.from.split(separator: ".").first.map(String.init)
                        Group {
                            if let up = upstream, case .scalar(let v) = state.dashOutputs[up] ?? .none {
                                StatPanelView(title: dash.props["title"] ?? (n.title ?? n.id), value: v)
                            } else if let up = upstream, case .timeSeries(let s) = state.dashOutputs[up] ?? .none {
                                StatPanelView(title: dash.props["title"] ?? (n.title ?? n.id), value: s.first?.points.last?.1 ?? 0)
                            } else {
                                VStack(alignment: .leading) { Text(dash.props["title"] ?? (n.title ?? n.id)).font(.caption); Text("No data").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                        .position(x: rectView.minX, y: rectView.minY)
                        .allowsHitTesting(false)
                    case .panelTable:
                        let upstream = vm.edges.first(where: { $0.to == n.id+".in" })?.from.split(separator: ".").first.map(String.init)
                        Group {
                            if let up = upstream, case .table(let rows) = state.dashOutputs[up] ?? .none {
                                TablePanelView(title: dash.props["title"] ?? (n.title ?? n.id), rows: rows)
                            } else {
                                VStack(alignment: .leading) { Text(dash.props["title"] ?? (n.title ?? n.id)).font(.caption); Text("No data").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                        .position(x: rectView.minX, y: rectView.minY)
                        .allowsHitTesting(false)
                    case .stageA4:
                        let origin = transform.docToView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
                        let rectView = CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w)*vm.zoom, height: CGFloat(n.h)*vm.zoom)
                        // Page shell
                        let page = dash.props["page"] ?? "A4"
                        let marginsStr = dash.props["margins"] ?? "18,18,18,18"
                        let baseline = CGFloat(Double(dash.props["baseline"] ?? "12") ?? 12)
                        StageView(title: dash.props["title"] ?? "The Stage",
                                  page: page,
                                  margins: parseInsets(marginsStr),
                                  baseline: baseline)
                            .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                            .position(x: rectView.minX, y: rectView.minY)
                            .allowsHitTesting(false)
                            .overlay(
                                Group {
                                    // Render upstream view payload inside page margins using WKWebView
                                    if let up = vm.edges.first(where: { $0.to == n.id+".in" })?.from.split(separator: ".").first.map(String.init),
                                       let payload = state.dashOutputs[up] {
                                        switch payload {
                                        case .view(let s):
                                            let pageSize: CGSize = {
                                                switch (page.lowercased()) {
                                                case "letter": return CGSize(width: 612, height: 792)
                                                default: return CGSize(width: 595, height: 842)
                                                }
                                            }()
                                            let m = parseInsets(marginsStr)
                                            let contentW = pageSize.width - m.leading - m.trailing
                                            let contentH = pageSize.height - m.top - m.bottom
                                            let scale = min(max(1, rectView.width) / pageSize.width, max(1, rectView.height) / pageSize.height)
                                            let contentRect = CGRect(
                                                x: rectView.minX + m.leading * scale,
                                                y: rectView.minY + m.top * scale,
                                                width: contentW * scale,
                                                height: contentH * scale
                                            )
                                            StageContentWebView(content: s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg") ? .svg(s) : .html(s))
                                                .frame(width: contentRect.width, height: contentRect.height, alignment: .topLeading)
                                                .position(x: contentRect.minX, y: contentRect.minY)
                                                .allowsHitTesting(false)
                                        default:
                                            EmptyView()
                                        }
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                // On-canvas double click → rename Stage via properties sheet
                                state.pendingEditNodeId = n.id
                            }
                    default: EmptyView()
                    }
                }
            }
        }
    }
    private func parseInsets(_ s: String) -> EdgeInsets {
        let parts = s.split(separator: ",").compactMap{ Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 4 { return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[3]) }
        return EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    }
}

fileprivate struct QuickActionsMenu: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack { // use VStack to avoid Group type inference issue
            if let sel = vm.selection, let kind = state.dashboard[sel]?.kind {
                switch kind {
                case .query:
                    Button("Connect ← Datasource") { connectFromLastDatasource(into: sel) }
                case .transform, .aggregator, .topN, .threshold:
                    Button("Connect ← Query/Transform") { connectFromLastSeriesNode(into: sel) }
                case .panelLine:
                    Button("Connect ← Series") { connectFromLastSeriesNode(into: sel) }
                case .panelStat:
                    Button("Connect ← Aggregator") { connectFromLastAggregator(into: sel) }
                case .panelTable:
                    Button("Connect ← TopN") { connectFromLastTopN(into: sel) }
                case .stageA4:
                    Button("Connect ← View") { connectIntoStage(into: sel) }
                    Menu("Connect to baseline…") {
                        let count = (vm.node(by: sel)?.ports.filter{ $0.dir == .input && $0.id.hasPrefix("in") }.count) ?? 0
                        let maxK = min(count, 64)
                        if maxK > 0 {
                            ForEach(0..<maxK, id: \.self) { k in
                                let label = vm.baselineIndexOneBased ? (k+1) : k
                                Button("\(label)") { connectIntoStage(into: sel, baselineZeroBased: k) }
                            }
                        } else {
                            Text("No baselines available").foregroundStyle(.secondary)
                        }
                    }
                case .datasource, .adapterFountain, .adapterScoreKit:
                    EmptyView()
                }
                Divider()
                Button("Bring to Front") { vm.bringToFront(ids: vm.selected.isEmpty ? [sel] : vm.selected) }
                Button("Send to Back") { vm.sendToBack(ids: vm.selected.isEmpty ? [sel] : vm.selected) }
                if state.dashboard[sel] != nil {
                    Button("Edit Properties…") { state.pendingEditNodeId = sel }
                }
            }
        }
    }
    private func lastId(where pred: (String, DashKind) -> Bool) -> String? {
        let ids = vm.nodes.map { $0.id }
        for id in ids.reversed() { if let k = state.dashboard[id]?.kind, pred(id, k) { return id } }
        return nil
    }
    private func connectFromLastDatasource(into id: String) {
        if let ds = lastId(where: { _, k in k == .datasource }) { _ = vm.ensureEdge(from: (ds,"out"), to: (id,"in")) }
    }
    private func connectFromLastSeriesNode(into id: String) {
        if let up = lastId(where: { _, k in k == .transform || k == .query || k == .aggregator || k == .topN || k == .threshold }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in")) }
    }
    private func connectOverlayFromLastThreshold(into id: String) {
        if let thr = lastId(where: { _, k in k == .threshold }) { _ = vm.ensureEdge(from: (thr,"out"), to: (id,"overlayIn")) }
    }
    private func connectFromLastAggregator(into id: String) {
        if let agg = lastId(where: { _, k in k == .aggregator }) { _ = vm.ensureEdge(from: (agg,"out"), to: (id,"in")) }
    }
    private func connectFromLastTopN(into id: String) {
        if let top = lastId(where: { _, k in k == .topN }) { _ = vm.ensureEdge(from: (top,"out"), to: (id,"in")) }
    }
    private func connectIntoStage(into id: String) {
        if let up = lastId(where: { _, k in k == .panelLine || k == .panelStat || k == .panelTable || k == .adapterFountain || k == .adapterScoreKit }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in0")) }
    }
    private func connectIntoStage(into id: String, baselineZeroBased k: Int) {
        if let up = lastId(where: { _, k in k == .panelLine || k == .panelStat || k == .panelTable || k == .adapterFountain || k == .adapterScoreKit }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in\(max(0,k))")) }
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
                let g = CGFloat(vm.grid)
                let x = CGFloat(vm.nodes[idx].x)
                let y = CGFloat(vm.nodes[idx].y)
                vm.nodes[idx].x = Int((round(x / g) * g))
                vm.nodes[idx].y = Int((round(y / g) * g))
                dragStart = nil
            }
    }

    @ViewBuilder
    private func flowEditorOverlay(docSize: CGSize) -> some View {
        let transform = CanvasTransform(scale: vm.zoom, translation: vm.translation)
        NodeEditor(patch: $flowPatch, selection: $flowSelection)
            .onNodeMoved { index, loc in
                guard index >= 0, index < flowNodeIds.count else { return }
                let nodeId = flowNodeIds[index]
                guard let i = vm.nodeIndex(by: nodeId) else { return }
                let g = CGFloat(vm.grid)
                vm.nodes[i].x = Int((round(loc.x / g) * g))
                vm.nodes[i].y = Int((round(loc.y / g) * g))
                // Trash hit testing in view-space
                let originView = transform.docToView(CGPoint(x: CGFloat(vm.nodes[i].x), y: CGFloat(vm.nodes[i].y)))
                let rectView = CGRect(x: originView.x, y: originView.y, width: CGFloat(vm.nodes[i].w) * vm.zoom, height: CGFloat(vm.nodes[i].h) * vm.zoom)
                let intersects = rectView.intersects(trashRectView)
                if trashHover != intersects { trashHover = intersects }
                // If center entered trash box, delete immediately (single or multi-selection)
                if intersects {
                    let id = vm.nodes[i].id
                    let idsToDelete: Set<String> = (!vm.selected.isEmpty && vm.selected.contains(id)) ? vm.selected : [id]
                        vm.deleteNodes(ids: idsToDelete)
                        trashHover = false
                    let center = CGPoint(x: rectView.midX, y: rectView.midY)
                    let puff = PuffItem(center: center)
                    puffItems.append(puff)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { puffItems.removeAll { $0.id == puff.id } }
                        for did in idsToDelete { state.removeDashNode(id: did); state.removeServerNode(id: did); state.closeRendererPreview(id: did) }
                }
            }
            .onWireAdded { wire in
                let srcId = vm.nodes[wire.output.nodeIndex].id
                let dstId = vm.nodes[wire.input.nodeIndex].id
                let outPorts = canonicalSortPorts(vm.nodes[wire.output.nodeIndex].ports.filter { $0.dir == .output })
                let inPorts = canonicalSortPorts(vm.nodes[wire.input.nodeIndex].ports.filter { $0.dir == .input })
                guard wire.output.portIndex < outPorts.count, wire.input.portIndex < inPorts.count else { return }
                let fromRef = srcId + "." + outPorts[wire.output.portIndex].id
                let toRef = dstId + "." + inPorts[wire.input.portIndex].id
                vm.ensureEdge(from: (srcId, outPorts[wire.output.portIndex].id), to: (dstId, inPorts[wire.input.portIndex].id))
                vm.transientGlowEdge(fromRef: fromRef, toRef: toRef)
                // Mirror to service (CreateLink property) only when both ends are service instruments
                Task { @MainActor in
                    if let c = state.api as? PatchBayClient {
                        let isServiceSrc = state.instruments.contains { $0.id == srcId }
                        let isServiceDst = state.instruments.contains { $0.id == dstId }
                        if isServiceSrc && isServiceDst {
                            let prop = Components.Schemas.PropertyLink(from: fromRef, to: toRef, direction: .a_to_b)
                            let create = Components.Schemas.CreateLink(kind: .property, property: prop, ump: nil)
                            _ = try? await c.createLink(create)
                            await state.refreshLinks()
                        }
                    }
                }
            }
            .onWireRemoved { wire in
                let srcId = vm.nodes[wire.output.nodeIndex].id
                let dstId = vm.nodes[wire.input.nodeIndex].id
                let outPorts = canonicalSortPorts(vm.nodes[wire.output.nodeIndex].ports.filter { $0.dir == .output })
                let inPorts = canonicalSortPorts(vm.nodes[wire.input.nodeIndex].ports.filter { $0.dir == .input })
                guard wire.output.portIndex < outPorts.count, wire.input.portIndex < inPorts.count else { return }
                let fromRef = srcId + "." + outPorts[wire.output.portIndex].id
                let toRef = dstId + "." + inPorts[wire.input.portIndex].id
                vm.edges.removeAll { $0.from == fromRef && $0.to == toRef }
                // Try to delete the corresponding link in the service (best-effort by match) when both ends are service instruments
                Task { @MainActor in
                    if let c = state.api as? PatchBayClient {
                        let isServiceSrc = state.instruments.contains { $0.id == srcId }
                        let isServiceDst = state.instruments.contains { $0.id == dstId }
                        if isServiceSrc && isServiceDst {
                            if let list = try? await c.listLinks() {
                                if let match = list.first(where: { $0.kind == .property && $0.property?.from == fromRef && $0.property?.to == toRef }) {
                                    try? await c.deleteLink(id: match.id)
                                    await state.refreshLinks()
                                }
                            }
                        }
                    }
                }
            }
            .onTransformChanged { pan, z in
                vm.zoom = CGFloat(z)
                vm.translation = CGPoint(x: pan.width, y: pan.height)
            }
    }

    // Overlays (zones/notes/health) removed in monitor mode
}
