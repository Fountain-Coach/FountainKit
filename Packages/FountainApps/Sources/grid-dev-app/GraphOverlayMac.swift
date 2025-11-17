import SwiftUI
import FountainStoreClient

struct GraphOverlayMac: View {
    struct Node: Identifiable { let id: String; let title: String; let x: CGFloat; let y: CGFloat }
    struct Edge: Identifiable { let id: String; let fromNode: String; let fromPort: String; let toNode: String; let toPort: String }

    @State private var nodes: [Node] = []
    @State private var edges: [Edge] = []
    @State private var scale: CGFloat = 1.0
    @State private var tx: CGFloat = 0.0
    @State private var ty: CGFloat = 0.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Noodles (under nodes)
            GeometryReader { geo in
                Path { path in
                    for e in edges {
                        guard let a = node(for: e.fromNode), let b = node(for: e.toNode) else { continue }
                        let x1 = (a.x + 120 + tx) * scale
                        let y1 = (a.y + 20 + ty) * scale
                        let x2 = (b.x + tx) * scale
                        let y2 = (b.y + 20 + ty) * scale
                        let mx = (x1 + x2) / 2
                        path.move(to: CGPoint(x: x1, y: y1))
                        path.addCurve(to: CGPoint(x: x2, y: y2), control1: CGPoint(x: mx, y: y1), control2: CGPoint(x: mx, y: y2))
                    }
                }
                .stroke(Color(red: 0.42, green: 0.54, blue: 0.97).opacity(0.8), lineWidth: 2)
            }
            // Nodes
            ForEach(nodes) { n in
                Text(n.title)
                    .font(.system(size: 12))
                    .frame(width: 120, height: 40)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                    .position(x: (n.x + 60 + tx) * scale, y: (n.y + 20 + ty) * scale)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .onAppear { loadGraph(); attachTransformListeners() }
    }

    private func node(for id: String) -> Node? { nodes.first { $0.id == id } }

    private func attachTransformListeners() {
        NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { n in
            guard let info = n.userInfo else { return }
            if let t = info["type"] as? String {
                if t == "ui.zoom" || t == "ui.zoom.debug" {
                    let z = (info["zoom"] as? NSNumber)?.doubleValue
                    let mag = (info["magnification"] as? NSNumber)?.doubleValue
                    Task { @MainActor in
                        if let z { self.scale = max(0.1, min(16.0, CGFloat(z))) }
                        if let mag { self.scale = max(0.1, min(16.0, self.scale * (1.0 + CGFloat(mag)))) }
                    }
                } else if t == "ui.pan" || t == "ui.pan.debug" {
                    let x = (info["x"] as? NSNumber)?.doubleValue
                    let y = (info["y"] as? NSNumber)?.doubleValue
                    let dx = (info["dx.doc"] as? NSNumber)?.doubleValue
                    let dy = (info["dy.doc"] as? NSNumber)?.doubleValue
                    Task { @MainActor in
                        if let x, let y { self.tx = CGFloat(x); self.ty = CGFloat(y) }
                        if let dx, let dy { self.tx += CGFloat(dx); self.ty += CGFloat(dy) }
                    }
                }
            }
        }
    }

    private func loadGraph() {
        Task { @MainActor in
            let store = resolveStore()
            // Try scene first, then fallback to prompt:patchbay-graph
            let candidates = [
                (corpus: "baseline-patchbay", id: "scene:patchbay-test:graph"),
                (corpus: "baseline-patchbay", id: "prompt:patchbay-graph:graph")
            ]
            var loaded: [String: Any]? = nil
            for c in candidates {
                if let data = try? await store.getDoc(corpusId: c.corpus, collection: "segments", id: c.id),
                   let s = String(data: data, encoding: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
                    loaded = obj; break
                }
            }
            if let obj = loaded {
                var outNodes: [Node] = []
                if let arr = obj["nodes"] as? [[String: Any]] {
                    for it in arr {
                        let id = (it["id"] as? String) ?? UUID().uuidString
                        let title = (it["displayName"] as? String) ?? (it["title"] as? String) ?? id
                        let x = CGFloat((it["x"] as? NSNumber)?.doubleValue ?? 100)
                        let y = CGFloat((it["y"] as? NSNumber)?.doubleValue ?? 100)
                        outNodes.append(Node(id: id, title: title, x: x, y: y))
                    }
                }
                var outEdges: [Edge] = []
                if let arr = obj["edges"] as? [[String: Any]] {
                    for it in arr {
                        let id = (it["id"] as? String) ?? UUID().uuidString
                        if let from = it["from"] as? [String: Any], let to = it["to"] as? [String: Any] {
                            let fn = (from["node"] as? String) ?? ""
                            let fp = (from["port"] as? String) ?? ""
                            let tn = (to["node"] as? String) ?? ""
                            let tp = (to["port"] as? String) ?? ""
                            outEdges.append(Edge(id: id, fromNode: fn, fromPort: fp, toNode: tn, toPort: tp))
                        }
                    }
                }
                self.nodes = outNodes
                self.edges = outEdges
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type": "overlay.graph.loaded", "nodes": outNodes.count, "edges": outEdges.count
                ])
            }
        }
    }

    private func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") { url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) }
            else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }
}
