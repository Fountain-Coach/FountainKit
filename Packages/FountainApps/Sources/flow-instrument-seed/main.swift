import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct FlowInstrumentSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        // Default to baseline-patchbay corpus
        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url: URL
                if dir.hasPrefix("~") { url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) }
                else { url = URL(fileURLWithPath: dir, isDirectory: true) }
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+flow"]) } catch { /* ignore */ }

        let pageId = "prompt:flow-instrument"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/flow-instrument", host: "store", title: "Flow Instrument — PatchBay Graph (Creation)")
        _ = try? await store.addPage(page)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))

        let mrtsId = "prompt:flow-instrument-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/flow-instrument-mrts", host: "store", title: "Flow — MRTS: Editor→Corpus Baseline Pipeline")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))

        if let facts = factsJSON() {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts))
        }

        await seedDefaultGraph(store: store, corpusId: corpusId)
        print("Seeded Flow Instrument prompts → corpus=\(corpusId) pages=[\(pageId), \(mrtsId)] + default graph")
    }

    static let creationPrompt = """
    Scene: Flow Instrument — PatchBay Graph (Ports, Noodles, Transforms)
    Text:

    - Identity: { manufacturer: Fountain, product: FlowInstrument, displayName: "Flow", instanceId: "flow-1" }.
    - Role: Typed graph that connects instrument outputs to inputs using “noodles”. Materializes deterministic pipelines (Editor → Corpus → Drift → Patterns → Reflection) and ad‑hoc routings. Runs on the same canvas as the grid.
    - UI (center pane canvas):
      • Nodes = instruments or transforms; each shows a title and port dots (left = inputs, right = outputs).
      • Noodles = curved lines from an output port to a compatible input port; hover highlights endpoints; incompatible endpoints show a blocked cursor.
      • Create nodes: palette/dnd or “+” context action; move nodes by dragging; zoom/pan per baseline gestures.
      • Create noodles: mousedown on an output port, drag to input port; abort on Esc or click away.
      • Selection/inspect: single‑click node/edge → Right pane shows PE snapshot and recent events (monitor tail).
    - Type system:
      • Kinds: text, baseline, drift, patterns, reflection, claims[], json, pe‑snapshot, bytes (opaque).
      • Compatibility: equal kinds or defined coercions (text → baseline via “Submit” transform; drift → patterns; patterns → reflection).
    - Transform nodes (built‑ins):
      • Submit (text→baseline): wraps editor.submit → corpus.baseline.add for active corpus/page.
      • Compute Drift: baseline→drift
      • Compute Patterns: drift→patterns
      • Compute Reflection: patterns→reflection
    - Events & routing:
      • Ports emit/consume event envelopes { kind, payload, ts, meta }.
      • On emit, Flow routes to downstream edges; for transforms, it calls the mapped vendor JSON operation on the destination instrument.
      • Monitor: “flow.edge.created”, “flow.edge.deleted”, “flow.forwarded” { source, target, kind, count }.
    - Property Exchange (PE):
      • flow.nodes[]: { id, displayName, product, ports[{ id, dir:in|out, kind }] }
      • flow.edges[]: { id, from:{node,port}, to:{node,port}, transformId? }
      • selected.nodeId?, selected.edgeId?
      • routing.enabled (0/1), routing.debounce.ms (int), autosave (0/1)
    - Vendor JSON (SysEx7 UMP):
      • flow.port.define { nodeId, portId, dir, kind }
      • flow.edge.create { from:{node,port}, to:{node,port}, transformId? }
      • flow.edge.delete { edgeId }
      • flow.node.add { nodeId, displayName, product }
      • flow.node.remove { nodeId }
      • flow.forward.test { from:{node,port}, payload:{…} }
    - Persistence:
      • Flow graph persisted as a page “flow:<appId>” in FountainStore; segments: graph.json (nodes/edges), facts (instrument registry).
      • PE snapshots for flow.* emitted and included in monitor (pe.get notify).
    - Web constraints:
      • Same graph behavior; editor remains in the left scroll pane; graph nodes render in center canvas; noodles/ports accessible via mouse.
    """

    static let mrtsPrompt = """
    Scene: Flow — MRTS: Editor→Corpus Baseline Pipeline
    Text:

    - Objective: verify deterministic noodling between instruments, type‑checks on ports, and end‑to‑end Corpus ops.
    - Steps:
        1. Reset graph (routing.enabled=0, flow.edges=[]), then enable routing.
        2. Define ports (if not auto):
           • Editor outputs: text.parsed.out (kind:text), text.content.out (kind:text)
           • Corpus inputs: editor.submit.in (kind:text), baseline.add.in (kind:baseline), drift.compute.in (kind:baseline), patterns.compute.in (kind:drift), reflection.compute.in (kind:patterns)
        3. Create noodle: Editor.text.parsed.out → Submit(text→baseline) → Corpus.baseline.add.in; routing.enabled=1.
        4. Send editor.submit via flow (or type in the editor then submit). Assert “corpus.baseline.added” monitor and baselines.total++ (PE).
        5. Create noodles: Corpus.baseline.added.out → drift.compute.in; drift.out → patterns.compute.in; patterns.out → reflection.compute.in. Trigger and assert each monitor event and PE update (latest ids, last.op, last.ts).
        6. Incompatible wiring test: attempt Editor.text.parsed.out → reflection.compute.in without Submit/Compute transforms; connection is blocked.
        7. Persistence round‑trip: Save graph; reload; assert flow.nodes/flow.edges via PE; re‑run a forward.test and assert routing.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "flow": [
                "products": ["FountainEditor","CorpusInstrument","Submit","ComputeDrift","ComputePatterns","ComputeReflection"],
                "portKinds": ["text","baseline","drift","patterns","reflection","json","pe-snapshot"],
                "vendorJSON": [
                    "flow.port.define","flow.edge.create","flow.edge.delete","flow.node.add","flow.node.remove","flow.forward.test"
                ],
                "invariants": ["typeSafeWiring","autosaveGraph","forwardEmitsMonitor","peSnapshotOnChange"]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }

    // Seed a default graph template (Editor → Submit → Corpus, and Editor → LLMAdapter)
    static func seedDefaultGraph(store: FountainStoreClient, corpusId: String) async {
        let pageId = "prompt:flow-instrument"
        let nodes: [[String: Any]] = [
            ["id": "n-editor", "displayName": "Fountain Editor", "product": "FountainEditor"],
            ["id": "n-corpus", "displayName": "Corpus Instrument", "product": "CorpusInstrument"],
            ["id": "n-submit", "displayName": "Submit", "product": "Submit"],
            ["id": "n-llm", "displayName": "LLM Adapter", "product": "LLMAdapter"],
        ]
        let edges: [[String: Any]] = [
            ["id": "e-editor-submit-corpus", "from": ["node": "n-editor", "port": "text.content.out"], "to": ["node": "n-corpus", "port": "baseline.add.in"], "transformId": "n-submit"],
            ["id": "e-editor-llm", "from": ["node": "n-editor", "port": "text.content.out"], "to": ["node": "n-llm", "port": "prompt.in"]]
        ]
        let graph: [String: Any] = ["nodes": nodes, "edges": edges]
        if let data = try? JSONSerialization.data(withJSONObject: graph, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):graph", pageId: pageId, kind: "graph.json", text: text))
        }
    }
}
