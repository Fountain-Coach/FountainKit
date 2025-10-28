import Foundation

@MainActor
final class DashboardExecutor: ObservableObject {
    // Public outputs keyed by node id
    @Published var outputs: [String: Payload] = [:]

    // Internal state
    private var registry: [String: DashNode] = [:]
    private var deps: [String: [String]] = [:] // nodeId -> upstream nodeIds (single for query/transform/panel)
    private var refresh: [String: Int] = [:]   // query id -> refresh seconds
    private var nextDue: [String: Date] = [:]  // query id -> next due time
    private var datasourceURL: [String: URL] = [:] // query id -> resolved baseURL

    func rebuild(vm: EditorVM, registry: [String:DashNode]) {
        self.registry = registry
        deps.removeAll(); refresh.removeAll(); nextDue.removeAll(); datasourceURL.removeAll()
        // Build deps graph from edges using canonical ports (out -> in)
        for e in vm.edges {
            let partsF = e.from.split(separator: ".", maxSplits: 1).map(String.init)
            let partsT = e.to.split(separator: ".", maxSplits: 1).map(String.init)
            guard partsF.count == 2, partsT.count == 2 else { continue }
            let src = partsF[0]; let dst = partsT[0]
            deps[dst, default: []].append(src)
        }
        // Initialize query schedules and datasource bindings
        for (id, node) in registry {
            switch node.kind {
            case .datasource:
                // Resolve its baseURL; queries upstream of panels will pick it up
                if let urlStr = node.props["baseURL"], let u = URL(string: urlStr) { datasourceURL[id] = u }
            case .query:
                let r = Int(node.props["refreshSeconds"] ?? "10") ?? 10
                refresh[id] = max(1, r)
                nextDue[id] = Date() // immediately due
            default: break
            }
            // Default payloads
            if outputs[id] == nil { outputs[id] = .none }
        }
    }

    func remove(ids: [String]) {
        for i in ids { outputs.removeValue(forKey: i); deps.removeValue(forKey: i); refresh.removeValue(forKey: i); nextDue.removeValue(forKey: i); registry.removeValue(forKey: i) }
    }

    func tick() async {
        let now = Date()
        // Resolve datasources for queries by walking 1 edge upstream (datasource -> query)
        for (id, node) in registry where node.kind == .query {
            // Find upstream datasource
            let ups = deps[id] ?? []
            if let dsId = ups.first(where: { registry[$0]?.kind == .datasource }), let base = registry[dsId]?.props["baseURL"], let url = URL(string: base) {
                datasourceURL[id] = url
            }
        }
        // Run due queries
        for (id, node) in registry where node.kind == .query {
            guard let due = nextDue[id], due <= now else { continue }
            let r = refresh[id] ?? 10
            nextDue[id] = now.addingTimeInterval(TimeInterval(r))
            // Evaluate
            guard let base = datasourceURL[id] else { outputs[id] = .text("Missing datasource"); continue }
            let promQL = node.props["promQL"] ?? ""
            let range = Int(node.props["rangeSeconds"] ?? "300") ?? 300
            let step = Int(node.props["stepSeconds"] ?? "15") ?? 15
            let end = Date(); let start = end.addingTimeInterval(TimeInterval(-range))
            do {
                let s = try await queryRange(baseURL: base, promQL: promQL, start: start, end: end, step: step)
                outputs[id] = .timeSeries(s)
            } catch {
                outputs[id] = .text("Query failed: \(error.localizedDescription)")
            }
        }
        // Transforms: pass-through with optional scale/offset
        for (id, node) in registry where node.kind == .transform {
            let ups = deps[id] ?? []
            guard let src = ups.first, let payload = outputs[src] else { outputs[id] = .none; continue }
            let scale = Double(node.props["scale"] ?? "1.0") ?? 1.0
            let offset = Double(node.props["offset"] ?? "0.0") ?? 0.0
            switch payload {
            case .timeSeries(let arr):
                let mapped = arr.map { ts in
                    let pts = ts.points.map { (t, y) in (t, y * scale + offset) }
                    return TimeSeries(points: pts)
                }
                outputs[id] = .timeSeries(mapped)
            case .text(let t): outputs[id] = .text(t)
            case .none: outputs[id] = .none
            }
        }
        // Panels consume upstream; they don’t emit.
    }
}

