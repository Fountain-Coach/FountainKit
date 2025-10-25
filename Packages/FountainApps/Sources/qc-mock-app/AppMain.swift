import SwiftUI
import AppKit

@main
struct QCMockApp: App {
    var body: some Scene {
        WindowGroup("QC Mock") {
            EditorHost()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
        .commands {
            CommandMenu("View") {
                Button("Fit to View") { NotificationCenter.default.post(name: .qcZoomFit, object: nil) }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("Actual Size (100%)") { NotificationCenter.default.post(name: .qcZoomOne, object: nil) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Zoom In") { NotificationCenter.default.post(name: .qcZoomIn, object: nil) }
                    .keyboardShortcut("=", modifiers: [.command])
                Button("Zoom Out") { NotificationCenter.default.post(name: .qcZoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: [.command])
            }
        }
    }
}

// MARK: - Model

struct QCDocument: Codable {
    struct Canvas: Codable { var width: Int = 900; var height: Int = 560; var theme: String = "light"; var grid: Int = 24 }
    struct Port: Codable, Identifiable, Hashable { var id: String; var side: Side; var dir: Dir; var type: String = "data" }
    struct Node: Codable, Identifiable, Hashable { var id: String; var title: String?; var x: Int; var y: Int; var w: Int; var h: Int; var ports: [Port] = [] }
    struct Edge: Codable, Identifiable, Hashable { var id: String { from+"→"+to }; var from: String; var to: String; var routing: String?; var width: Double?; var glow: Bool? }
    enum Side: String, Codable, CaseIterable { case left,right,top,bottom }
    enum Dir: String, Codable, CaseIterable { case input = "in", output = "out" }

    var canvas: Canvas = .init()
    var nodes: [Node] = []
    var edges: [Edge] = []
    var notes: [Note] = []
    var autolayout: String = "none"
    struct Note: Codable { var text: String; var x: Int; var y: Int }
}

extension QCDocument.Node {
    var titleOrID: String { title ?? id }
}

// MARK: - View Model

@MainActor
final class EditorState: ObservableObject {
    @Published var doc = QCDocument()
    @Published var selection: String? = nil
    @Published var connectMode: Bool = false
    @Published var pendingFrom: (node: String, port: String)? = nil
    @Published var zoom: CGFloat = 1.0
    @Published var pan: CGSize = .zero
    @Published var panMode: Bool = false
    @Published var autoScale: Bool = true
    @Published var panHold: Bool = false // true while spacebar held

    // Service wiring
    let client = QCMClient()
    @Published var useService = true

    // Convenience
    func node(by id: String) -> QCDocument.Node? { doc.nodes.first{ $0.id == id } }
    func nodeIndex(by id: String) -> Int? { doc.nodes.firstIndex{ $0.id == id } }
    func portPosition(node n: QCDocument.Node, port p: QCDocument.Port) -> CGPoint {
        let x = CGFloat(n.x), y = CGFloat(n.y), w = CGFloat(n.w), h = CGFloat(n.h)
        switch p.side {
        case .left:   return CGPoint(x: x, y: y + h*0.5)
        case .right:  return CGPoint(x: x + w, y: y + h*0.5)
        case .top:    return CGPoint(x: x + w*0.5, y: y)
        case .bottom: return CGPoint(x: x + w*0.5, y: y + h)
        }
    }

    func addNode(at pt: CGPoint) {
        let grid = max(4, doc.canvas.grid)
        let snap: (CGFloat)->Int = { Int((($0 / CGFloat(grid)).rounded()) * CGFloat(grid)) }
        let nid = uniqueNodeID(prefix: "Node")
        let (x, y) = (snap(pt.x), snap(pt.y))
        if useService {
            Task { @MainActor in
                _ = try? await client.createNode(id: nid, title: nid, x: x, y: y, w: grid*10, h: grid*6)
                if let g = try? await client.exportJSON() { self.doc = QCDocument.from(g) }
                self.selection = nid
            }
        } else {
            let node = QCDocument.Node(id: nid, title: nid, x: x, y: y, w: grid*10, h: grid*6, ports: [])
            doc.nodes.append(node)
            selection = node.id
        }
    }

    func uniqueNodeID(prefix: String) -> String {
        var idx = doc.nodes.count + 1
        var candidate: String
        repeat { candidate = "\(prefix)_\(idx)"; idx += 1 } while doc.nodes.contains{ $0.id == candidate }
        return candidate
    }

    func addPort(to nodeID: String, side: QCDocument.Side, dir: QCDocument.Dir, id: String, type: String) {
        if useService {
            Task { @MainActor in
                let port = Components.Schemas.Port(id: id, side: .init(rawValue: side.rawValue) ?? .left, dir: (dir == .input ? ._in : .out), _type: .init(rawValue: type) ?? .data)
                _ = try? await client.addPort(nodeId: nodeID, port: port)
                if let g = try? await client.exportJSON() { self.doc = QCDocument.from(g) }
            }
        } else {
            guard let i = nodeIndex(by: nodeID) else { return }
            if doc.nodes[i].ports.contains(where: { $0.id == id }) { return }
            doc.nodes[i].ports.append(.init(id: id, side: side, dir: dir, type: type))
        }
    }

    func addEdge(from: (String,String), to: (String,String)) {
        if useService {
            Task { @MainActor in
                _ = try? await client.createEdge(from: "\(from.0).\(from.1)", to: "\(to.0).\(to.1)")
                if let g = try? await client.exportJSON() { self.doc = QCDocument.from(g) }
            }
        } else {
            let e = QCDocument.Edge(from: "\(from.0).\(from.1)", to: "\(to.0).\(to.1)", routing: "qcBezier", width: 2.0, glow: false)
            doc.edges.append(e)
        }
    }

    // Serialization
    func exportJSON() throws -> Data { try JSONEncoder().encode(doc) }

    func exportDSL() -> String {
        var out: [String] = []
        let c = doc.canvas
        out.append("canvas \(c.width)x\(c.height) theme=\(c.theme) grid=\(c.grid)")
        out.append("")
        for n in doc.nodes {
            out.append("node \(n.id) at (\(n.x),\(n.y)) size (\(n.w),\(n.h)) {")
            for p in n.ports {
                out.append("  port \(p.dir.rawValue) \(p.side.rawValue) name:\(p.id) type:\(p.type)")
            }
            out.append("}")
            out.append("")
        }
        for e in doc.edges {
            out.append("edge \(e.from) -> \(e.to) style \(e.routing ?? "qcBezier") width=\(e.width ?? 2.0)\( (e.glow ?? false) ? " glow" : "")")
        }
        out.append("")
        out.append("autolayout \(doc.autolayout)")
        return out.joined(separator: "\n")
    }

    func importJSON(_ data: Data) throws { doc = try JSONDecoder().decode(QCDocument.self, from: data) }

    // Compute square content bounds (with margin) for auto-scaling
    func contentBounds(margin: CGFloat = 40) -> CGRect {
        guard !doc.nodes.isEmpty else {
            let s = CGFloat(doc.canvas.grid * 20)
            return CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: -margin, dy: -margin)
        }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNormalMagnitude
        var maxY = CGFloat.leastNormalMagnitude
        for n in doc.nodes {
            minX = min(minX, CGFloat(n.x))
            minY = min(minY, CGFloat(n.y))
            maxX = max(maxX, CGFloat(n.x + n.w))
            maxY = max(maxY, CGFloat(n.y + n.h))
        }
        var rect = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        rect = rect.insetBy(dx: -margin, dy: -margin)
        let side = max(rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        return CGRect(x: cx - side/2, y: cy - side/2, width: side, height: side)
    }
}

// MARK: - Editor Host

struct EditorHost: View {
    @StateObject var state = EditorState()
    @State private var showingAddPort = false
    @State private var newPort: (side: QCDocument.Side, dir: QCDocument.Dir, id: String, type: String) = (.left, .input, "in", "data")

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Left: Outline
            List(selection: $state.selection) {
                Section("Nodes") {
                    ForEach(state.doc.nodes) { n in
                        Text(n.titleOrID).tag(n.id as String?)
                    }
                    .onDelete { indexSet in
                        if state.useService {
                            Task { @MainActor in
                                for i in indexSet.sorted(by: >) {
                                    let id = state.doc.nodes[i].id
                                    try? await state.client.deleteNode(id: id)
                                    if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
                                }
                            }
                        } else {
                            for i in indexSet.sorted(by: >) { state.doc.nodes.remove(at: i) }
                        }
                    }
                }
                Section("Edges") {
                    ForEach(state.doc.edges) { e in
                        Text("\(e.from) → \(e.to)")
                    }
                    .onDelete { indexSet in
                        if state.useService {
                            Task { @MainActor in
                                for i in indexSet.sorted(by: >) {
                                    let id = state.doc.edges[i].id
                                    try? await state.client.deleteEdge(id: id)
                                    if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
                                }
                            }
                        } else {
                            for i in indexSet.sorted(by: >) { state.doc.edges.remove(at: i) }
                        }
                    }
                }
            }
            .frame(minWidth: 220)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            .toolbar { toolbarContent }
        } content: {
            // Center: Canvas takes full right-side middle pane
            EditorCanvas()
                .environmentObject(state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .navigationSplitViewColumnWidth(min: 500, ideal: 900, max: .infinity)
        } detail: {
            // Right: Inspector
            Inspector()
                .environmentObject(state)
                .frame(minWidth: 260, maxWidth: 360, maxHeight: .infinity)
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor))
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .sheet(isPresented: $showingAddPort) {
            AddPortSheet(newPort: $newPort) { side, dir, id, type in
                if let nid = state.selection { state.addPort(to: nid, side: side, dir: dir, id: id, type: type) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .qcPanHold)) { note in
            if let down = note.userInfo?["down"] as? Bool { state.panHold = down }
        }
        .onReceive(NotificationCenter.default.publisher(for: .qcPanDelta)) { note in
            guard state.useService, let dx = note.userInfo?["dx"] as? Double, let dy = note.userInfo?["dy"] as? Double else { return }
            Task { @MainActor in try? await state.client.panBy(dx: dx, dy: dy); if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .qcZoomFit)) { _ in
            if state.useService { Task { @MainActor in try? await state.client.zoomFit(); if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) } } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .qcZoomOne)) { _ in
            if state.useService { Task { @MainActor in try? await state.client.zoomActual(anchor: nil); if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) } } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .qcZoomIn)) { _ in
            if state.useService {
                Task { @MainActor in
                    let newScale = min(3.0, Double(state.zoom) + 0.1)
                    try? await state.client.zoomSet(scale: newScale)
                    if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .qcZoomOut)) { _ in
            if state.useService {
                Task { @MainActor in
                    let newScale = max(0.25, Double(state.zoom) - 0.1)
                    try? await state.client.zoomSet(scale: newScale)
                    if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
                }
            }
        }
        .task {
            // Initial sync from service when available
            if state.useService, let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                // add node roughly center
                state.addNode(at: CGPoint(x: 200, y: 160))
            } label: { Label("New Node", systemImage: "square.dashed") }

            Button {
                showingAddPort = true
            } label: { Label("Add Port", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            .disabled(state.selection == nil)

            Toggle(isOn: $state.connectMode) { Label("Connect", systemImage: state.connectMode ? "link" : "link.badge.plus") }

            Toggle(isOn: $state.panMode) { Label("Pan", systemImage: state.panMode ? "hand.draw.fill" : "hand.draw") }
                .help("When enabled, drag on canvas pans the artboard")

            HStack(spacing: 4) {
                Button { withAnimation { state.zoom = max(0.25, state.zoom - 0.1) } } label: { Image(systemName: "minus.magnifyingglass") }
                Slider(value: Binding(get: { Double(state.zoom) }, set: { state.zoom = CGFloat($0) }), in: 0.25...3.0, step: 0.05)
                    .frame(width: 160)
                Button { withAnimation { state.zoom = min(3.0, state.zoom + 0.1) } } label: { Image(systemName: "plus.magnifyingglass") }
            }

            Toggle(isOn: $state.autoScale) { Label("Auto Scale", systemImage: "aspectratio") }

            Spacer()
            Button { saveKit() } label: { Label("Save Kit", systemImage: "square.and.arrow.down") }
            Button { loadKit() } label: { Label("Load Kit", systemImage: "folder") }
        }
    }

    func saveKit() {
        let panel = NSSavePanel()
        panel.title = "Save QC Kit"
        panel.nameFieldStringValue = "qc_prompt.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                do {
                    if state.useService, let g = try await state.client.exportJSON() {
                        let data = try JSONEncoder().encode(g)
                        try data.write(to: url)
                        let dslURL = url.deletingLastPathComponent().appendingPathComponent("qc_prompt.dsl")
                        // For now, synthesize DSL from current app view
                        try state.exportDSL().data(using: .utf8)?.write(to: dslURL)
                    } else {
                        // Local fallback
                        let data = try state.exportJSON()
                        try data.write(to: url)
                        let dslURL = url.deletingLastPathComponent().appendingPathComponent("qc_prompt.dsl")
                        try state.exportDSL().data(using: .utf8)?.write(to: dslURL)
                    }
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    func loadKit() {
        let panel = NSOpenPanel()
        panel.title = "Open qc_prompt.json"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url)
                    if state.useService {
                        // Decode GraphDoc and import through service
                        let g = try JSONDecoder().decode(Components.Schemas.GraphDoc.self, from: data)
                        _ = try await state.client.importJSON(body: .json(g))
                        if let ng = try? await state.client.exportJSON() { state.doc = QCDocument.from(ng) }
                    } else {
                        try state.importJSON(data)
                    }
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
}

// MARK: - Canvas

struct EditorCanvas: View {
    @EnvironmentObject var state: EditorState
    @State private var dragStartPos: CGPoint? = nil

    var body: some View {
        let artboard = state.contentBounds()
        ZoomScrollView(contentSize: CGSize(width: artboard.width, height: artboard.height), fitToVisible: state.autoScale, zoom: $state.zoom) {
            CanvasDocumentView(artboard: artboard)
                .environmentObject(state)
        }
    }
}

// A doc-space rendering of the canvas content (origin at artboard.topLeft)
struct CanvasDocumentView: View {
    @EnvironmentObject var state: EditorState
    var artboard: CGRect
    @State private var dragStart: CGPoint? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridBackground(size: CGSize(width: artboard.width, height: artboard.height), grid: CGFloat(max(4, state.doc.canvas.grid)), scale: state.zoom)
            // Edges
            ForEach(state.doc.edges) { e in
                DocEdgeView(edge: e, artboard: artboard)
            }
            // Nodes
            ForEach(state.doc.nodes) { n in
                NodeView(node: n, selected: state.selection == n.id)
                    .position(x: CGFloat(n.x - Int(artboard.minX) + n.w/2), y: CGFloat(n.y - Int(artboard.minY) + n.h/2))
                    .highPriorityGesture(nodeDragGesture(node: n))
                    .onTapGesture { state.selection = n.id }
            }
        }
        .environment(\.canvasTransform, CanvasTransform(scale: state.zoom, translation: .zero))
        .frame(width: artboard.width, height: artboard.height, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
    }

    func nodeDragGesture(node: QCDocument.Node) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                guard let idx = state.nodeIndex(by: node.id) else { return }
                if dragStart == nil { dragStart = CGPoint(x: node.x, y: node.y) }
                let start = dragStart ?? CGPoint(x: node.x, y: node.y)
                // Convert view-space deltas to doc-space deltas using current zoom
                let dx = v.translation.width / max(0.0001, state.zoom)
                let dy = v.translation.height / max(0.0001, state.zoom)
                let nowX = CGFloat(start.x) + dx
                let nowY = CGFloat(start.y) + dy
                state.doc.nodes[idx].x = Int(nowX)
                state.doc.nodes[idx].y = Int(nowY)
            }
            .onEnded { _ in
                guard let idx = state.nodeIndex(by: node.id) else { dragStart = nil; return }
                let grid = CGFloat(max(4, state.doc.canvas.grid))
                let x = CGFloat(state.doc.nodes[idx].x)
                let y = CGFloat(state.doc.nodes[idx].y)
                state.doc.nodes[idx].x = Int((round(x / grid) * grid))
                state.doc.nodes[idx].y = Int((round(y / grid) * grid))
                if state.useService {
                    Task { @MainActor in
                        _ = try? await state.client.patchNode(
                            path: .init(id: node.id),
                            headers: .init(),
                            body: .json(.init(title: node.title ?? nil,
                                              x: state.doc.nodes[idx].x,
                                              y: state.doc.nodes[idx].y,
                                              w: state.doc.nodes[idx].w,
                                              h: state.doc.nodes[idx].h))
                        )
                    }
                }
                dragStart = nil
            }
    }
}

struct DocEdgeView: View {
    var edge: QCDocument.Edge
    var artboard: CGRect
    @EnvironmentObject var state: EditorState
    var body: some View {
        Path { p in
            guard let (n1, p1) = lookup(edge.from), let (n2, p2) = lookup(edge.to) else { return }
            var a = state.portPosition(node: n1, port: p1)
            var b = state.portPosition(node: n2, port: p2)
            a.x -= artboard.minX; a.y -= artboard.minY
            b.x -= artboard.minX; b.y -= artboard.minY
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
        .stroke(Color.accentColor.opacity(edge.glow == true ? 0.5 : 1.0), lineWidth: CGFloat(edge.width ?? 2.0))
    }
    func lookup(_ ref: String) -> (QCDocument.Node, QCDocument.Port)? {
        let comps = ref.split(separator: ".", maxSplits: 1).map(String.init)
        guard comps.count == 2, let n = state.node(by: comps[0]), let p = n.ports.first(where: { $0.id == comps[1] }) else { return nil }
        return (n, p)
    }
}

struct GridBackground: View {
    var size: CGSize; var grid: CGFloat; var scale: CGFloat = 1.0
    var body: some View {
        Canvas { ctx, sz in
            let W = sz.width, H = sz.height
            let g1 = Color(NSColor.quaternaryLabelColor)
            let g5 = Color(NSColor.tertiaryLabelColor)
            var labels: [(CGPoint, String)] = []
            let minorStepView = grid * max(scale, 0.0001)
            let majorStepView = minorStepView * 5.0
            let showMinor = minorStepView >= 8.0
            let showLabels = majorStepView >= 12.0
            var i = 0 as Int
            var x: CGFloat = 0
            while x <= W {
                if showMinor || i % 5 == 0 {
                    var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: H))
                    ctx.stroke(p, with: .color((i % 5 == 0) ? g5 : g1), lineWidth: 1)
                }
                if showLabels && i % 5 == 0 { labels.append((CGPoint(x: x+2, y: 10), "\(Int(x))")) }
                i += 1; x += grid
            }
            i = 0; var y: CGFloat = 0
            while y <= H {
                if showMinor || i % 5 == 0 {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: W, y: y))
                    ctx.stroke(p, with: .color((i % 5 == 0) ? g5 : g1), lineWidth: 1)
                }
                if showLabels && i % 5 == 0 { labels.append((CGPoint(x: 4, y: y-2), "\(Int(y))")) }
                i += 1; y += grid
            }
            for (pt, s) in labels {
                ctx.draw(Text(s).font(.system(size: 9)).foregroundColor(.secondary), at: pt)
            }
        }
    }
}

struct NodeView: View {
    var node: QCDocument.Node
    var selected: Bool
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: selected ? 2 : 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            VStack(alignment: .center, spacing: 4) {
                Text(node.titleOrID).font(.system(size: 12, weight: .semibold))
                    .padding(.top, 6)
                PortsView(node: node)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: CGFloat(node.w), height: CGFloat(node.h))
    }
}

struct PortsView: View {
    var node: QCDocument.Node
    var body: some View {
        ZStack {
            ForEach(node.ports) { p in
                PortDot(port: p, node: node)
            }
        }
    }
}

struct PortDot: View {
    var port: QCDocument.Port; var node: QCDocument.Node
    @Environment(\.canvasTransform) private var xform
    var body: some View {
        let pos: CGPoint = {
            let x = CGFloat(node.x), y = CGFloat(node.y), w = CGFloat(node.w), h = CGFloat(node.h)
            switch port.side {
            case .left:   return CGPoint(x: w*0.0, y: h*0.5)
            case .right:  return CGPoint(x: w*1.0, y: h*0.5)
            case .top:    return CGPoint(x: w*0.5, y: 0)
            case .bottom: return CGPoint(x: w*0.5, y: h*1.0)
            }
        }()
        // Non-scaling radius for legibility
        let r: CGFloat = max(3, 7 / max(0.25, xform.scale))
        return Circle().fill(Color(NSColor.secondaryLabelColor))
            .frame(width: r, height: r)
            .position(x: pos.x, y: pos.y)
            .overlay(Text(port.id).font(.system(size: 8)).foregroundColor(.secondary)
                        .offset(x: port.side == .left ? -10 : 10, y: port.side == .top ? -10 : 10)
                        , alignment: .center)
    }
}

struct EdgeView: View {
    var edge: QCDocument.Edge
    @EnvironmentObject var state: EditorState
    var body: some View {
        Path { p in
            guard let (n1, p1) = lookup(edge.from), let (n2, p2) = lookup(edge.to) else { return }
            let a = state.portPosition(node: n1, port: p1)
            let b = state.portPosition(node: n2, port: p2)
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
        .stroke(Color.accentColor.opacity(edge.glow == true ? 0.5 : 1.0), lineWidth: CGFloat(edge.width ?? 2.0))
    }
    func lookup(_ ref: String) -> (QCDocument.Node, QCDocument.Port)? {
        let comps = ref.split(separator: ".", maxSplits: 1).map(String.init)
        guard comps.count == 2, let n = state.node(by: comps[0]), let p = n.ports.first(where: { $0.id == comps[1] }) else { return nil }
        return (n, p)
    }
}

// MARK: - Inspector & Sheets

struct Inspector: View {
    @EnvironmentObject var state: EditorState
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Canvas").font(.headline)
                Stepper(value: $state.doc.canvas.grid, in: 4...128, step: 4) {
                    Text("Grid: \(state.doc.canvas.grid)")
                }
                .onChange(of: state.doc.canvas.grid) { newValue in
                    if state.useService {
                        Task { @MainActor in
                            do { _ = try await state.client.patchCanvas(gridStep: newValue, autoScale: nil) } catch {}
                            if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
                        }
                    }
                }
            }
            Divider()
            if let sel = state.selection, let i = state.nodeIndex(by: sel) {
                VStack(alignment: .leading) {
                    Text("Node").font(.headline)
                    TextField("ID", text: Binding(get: { state.doc.nodes[i].id }, set: { state.doc.nodes[i].id = $0 }))
                        .textFieldStyle(.roundedBorder)
                    TextField("Title", text: Binding(get: { state.doc.nodes[i].title ?? "" }, set: { state.doc.nodes[i].title = $0 }))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Stepper(value: Binding(get: { state.doc.nodes[i].w }, set: { state.doc.nodes[i].w = $0 }), in: 40...2000, step: state.doc.canvas.grid) { Text("W: \(state.doc.nodes[i].w)") }
                        Stepper(value: Binding(get: { state.doc.nodes[i].h }, set: { state.doc.nodes[i].h = $0 }), in: 40...2000, step: state.doc.canvas.grid) { Text("H: \(state.doc.nodes[i].h)") }
                    }
                    .onChange(of: state.doc.nodes[i].w) { _ in
                        if state.useService { Task { @MainActor in _ = try? await state.client.patchNode(path: .init(id: state.doc.nodes[i].id), headers: .init(), body: .json(.init(title: state.doc.nodes[i].title ?? nil, x: state.doc.nodes[i].x, y: state.doc.nodes[i].y, w: state.doc.nodes[i].w, h: state.doc.nodes[i].h))) } }
                    }
                    .onChange(of: state.doc.nodes[i].h) { _ in
                        if state.useService { Task { @MainActor in _ = try? await state.client.patchNode(path: .init(id: state.doc.nodes[i].id), headers: .init(), body: .json(.init(title: state.doc.nodes[i].title ?? nil, x: state.doc.nodes[i].x, y: state.doc.nodes[i].y, w: state.doc.nodes[i].w, h: state.doc.nodes[i].h))) } }
                    }

                    Divider()
                    Text("Ports").font(.subheadline)
                    ForEach(state.doc.nodes[i].ports, id: \.id) { p in
                        HStack {
                            Text("\(p.id) • \(p.dir.rawValue) • \(p.side.rawValue) • \(p.type)")
                            Spacer()
                            Button { 
                                if state.useService {
                                    Task { @MainActor in
                                        _ = try? await state.client.removePort(nodeId: state.doc.nodes[i].id, portId: p.id)
                                        if let g = try? await state.client.exportJSON() { state.doc = QCDocument.from(g) }
                                    }
                                } else {
                                    if let idx = state.nodeIndex(by: state.doc.nodes[i].id) { state.doc.nodes[idx].ports.removeAll{ $0.id == p.id } }
                                }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } else {
                Text("Select a node to edit…").foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct AddPortSheet: View {
    @Binding var newPort: (side: QCDocument.Side, dir: QCDocument.Dir, id: String, type: String)
    var onAdd: (QCDocument.Side, QCDocument.Dir, String, String)->Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Port").font(.headline)
            HStack { Text("ID").frame(width: 60, alignment: .leading); TextField("id", text: $newPort.id).textFieldStyle(.roundedBorder) }
            HStack {
                Text("Side").frame(width: 60, alignment: .leading)
                Picker("", selection: $newPort.side) {
                    ForEach(QCDocument.Side.allCases, id: \.self) { Text($0.rawValue) }
                }.pickerStyle(.segmented)
            }
            HStack {
                Text("Dir").frame(width: 60, alignment: .leading)
                Picker("", selection: $newPort.dir) {
                    ForEach(QCDocument.Dir.allCases, id: \.self) { Text($0.rawValue) }
                }.pickerStyle(.segmented)
            }
            HStack { Text("Type").frame(width: 60, alignment: .leading); TextField("data/event/audio/midi", text: $newPort.type).textFieldStyle(.roundedBorder) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    onAdd(newPort.side, newPort.dir, newPort.id, newPort.type)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
