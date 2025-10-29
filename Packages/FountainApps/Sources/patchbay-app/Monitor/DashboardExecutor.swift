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
        // Adapters: push view payloads (stateless; recompute every tick)
        for (id, node) in registry where node.kind == .adapterFountain {
            if let path = node.props["source"], !path.isEmpty {
                do {
                    let svg = try AdapterFountainToTeatro.render(path: path)
                    outputs[id] = .view(svg)
                } catch {
                    outputs[id] = .text("Fountain adapter failed: \(error.localizedDescription)")
                }
            } else {
                outputs[id] = .text("Missing source path")
            }
        }
        for (id, node) in registry where node.kind == .adapterScoreKit {
            if let path = node.props["source"], !path.isEmpty {
                // For now, treat .svg as a direct view; otherwise, emit an informational text.
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let s = String(data: data, encoding: .utf8), s.contains("<svg") {
                    outputs[id] = .view(s)
                } else {
                    outputs[id] = .text("ScoreKit adapter: supply an SVG for now")
                }
            } else {
                outputs[id] = .text("Missing source path")
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
            case .scalar(let v): outputs[id] = .scalar(v * scale + offset)
            case .table(let rows): outputs[id] = .table(rows.map { TableRow(label: $0.label, value: $0.value * scale + offset) })
            case .annotations(let anns): outputs[id] = .annotations(anns)
            case .text(let t): outputs[id] = .text(t)
            case .view(let s): outputs[id] = .view(s)
            case .none: outputs[id] = .none
            }
        }
        // Aggregator: timeSeries -> scalar (avg/last/min/max)
        for (id, node) in registry where node.kind == .aggregator {
            let ups = deps[id] ?? []
            guard let src = ups.first, let payload = outputs[src] else { outputs[id] = .none; continue }
            let op = (node.props["op"] ?? "last").lowercased()
            switch payload {
            case .timeSeries(let arr):
                let lastVals = arr.compactMap { $0.points.last?.1 }
                if lastVals.isEmpty { outputs[id] = .scalar(0) }
                else {
                    let val: Double
                    switch op {
                    case "avg": val = lastVals.reduce(0,+) / Double(lastVals.count)
                    case "min": val = lastVals.min() ?? 0
                    case "max": val = lastVals.max() ?? 0
                    default: val = lastVals.last ?? 0
                    }
                    outputs[id] = .scalar(val)
                }
            default:
                outputs[id] = .text("Aggregator expects timeSeries")
            }
        }
        // TopN: timeSeries -> table sorted by last value
        for (id, node) in registry where node.kind == .topN {
            let ups = deps[id] ?? []
            guard let src = ups.first, let payload = outputs[src] else { outputs[id] = .none; continue }
            let n = Int(node.props["n"] ?? "5") ?? 5
            switch payload {
            case .timeSeries(let arr):
                let rows = arr.enumerated().compactMap { (i, ts) -> TableRow? in
                    guard let last = ts.points.last?.1 else { return nil }
                    return TableRow(label: "series_\(i+1)", value: last)
                }
                outputs[id] = .table(Array(rows.sorted { $0.value > $1.value }.prefix(max(0, n))))
            default:
                outputs[id] = .text("TopN expects timeSeries")
            }
        }
        // Threshold: timeSeries -> annotations when last value exceeds threshold
        for (id, node) in registry where node.kind == .threshold {
            let ups = deps[id] ?? []
            guard let src = ups.first, let payload = outputs[src] else { outputs[id] = .none; continue }
            let thr = Double(node.props["threshold"] ?? "0") ?? 0
            switch payload {
            case .timeSeries(let arr):
                var anns: [Annotation] = []
                for (i, ts) in arr.enumerated() {
                    if let (t, y) = ts.points.last, y > thr { anns.append(Annotation(time: t, text: "series_\(i+1) > \(thr)")) }
                }
                outputs[id] = .annotations(anns)
            default:
                outputs[id] = .text("Threshold expects timeSeries")
            }
        }
        // Panels consume upstream; they don’t emit.
    }
}
