import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PatchbayTestSceneSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let store = resolveStore()
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+scene"]) } catch { }

        let pageId = "scene:patchbay-test"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://scene/patchbay-test", host: "store", title: "PatchBay Test Scene")
        _ = try? await store.addPage(page)
        // Creation (visual + host protocol)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))

        // Test scene script (.fountain)
        let text = """
        INT. ROOM — DAY
        JOHN
        (whispering)
        Hello.
        He sits.
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):script.fountain", pageId: pageId, kind: "text.fountain", text: text))

        // Graph to exercise routing: Editor → Submit → Corpus; Editor → LLM
        let nodes: [[String: Any]] = [
            ["id": "n-editor", "displayName": "Fountain Editor", "product": "FountainEditor", "x": 100, "y": 100],
            ["id": "n-submit", "displayName": "Submit", "product": "Submit", "x": 380, "y": 120],
            ["id": "n-corpus", "displayName": "Corpus Instrument", "product": "CorpusInstrument", "x": 640, "y": 100],
            ["id": "n-llm", "displayName": "LLM Adapter", "product": "LLMAdapter", "x": 640, "y": 280],
        ]
        let edges: [[String: Any]] = [
            ["id": "e-editor-submit", "from": ["node": "n-editor", "port": "text.content.out"], "to": ["node": "n-corpus", "port": "baseline.add.in"], "transformId": "n-submit"],
            ["id": "e-editor-llm", "from": ["node": "n-editor", "port": "text.content.out"], "to": ["node": "n-llm", "port": "prompt.in"]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: ["nodes": nodes, "edges": edges], options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):graph", pageId: pageId, kind: "graph.json", text: s))
        }

        // Playbook: recommended vendor ops for this scene (host + instruments)
        let playbook: [[String: Any]] = [
            ["target": "PatchBay Canvas", "topic": "flow.node.add", "data": ["nodeId": "n-editor", "displayName": "Fountain Editor", "product": "FountainEditor"]],
            ["target": "PatchBay Canvas", "topic": "flow.node.add", "data": ["nodeId": "n-submit", "displayName": "Submit", "product": "Submit"]],
            ["target": "PatchBay Canvas", "topic": "flow.node.add", "data": ["nodeId": "n-corpus", "displayName": "Corpus Instrument", "product": "CorpusInstrument"]],
            ["target": "PatchBay Canvas", "topic": "flow.node.add", "data": ["nodeId": "n-llm", "displayName": "LLM Adapter", "product": "LLMAdapter"]],
            ["target": "PatchBay Canvas", "topic": "flow.edge.create", "data": ["edgeId": "e-editor-submit", "from": ["node": "n-editor", "port": "text.content.out"], "to": ["node": "n-corpus", "port": "baseline.add.in"], "transformId": "n-submit"]],
            ["target": "PatchBay Canvas", "topic": "flow.edge.create", "data": ["edgeId": "e-editor-llm", "from": ["node": "n-editor", "port": "text.content.out"], "to": ["node": "n-llm", "port": "prompt.in"]]],
            ["target": "Fountain Editor", "topic": "text.set", "data": ["text": text + "\n", "cursor": (text as NSString).length]],
            ["target": "Fountain Editor", "topic": "editor.submit", "data": [:]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: playbook, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):playbook.json", pageId: pageId, kind: "playbook.json", text: s))
        }

        // Facts with expected monitors
        let facts: [String: Any] = [
            "expect": [
                "monitors": ["text.parsed", "corpus.baseline.added", "llm.chat.started", "llm.chat.completed"],
                "editor.wrapColumnRange": [58, 62]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: s))
        }

        // MRTS page
        let mrtsId = "scene:patchbay-test-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://scene/patchbay-test-mrts", host: "store", title: "PatchBay Test Scene — MRTS")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))

        print("Seeded PatchBay Test Scene → corpus=\(corpusId) pageId=\(pageId) + MRTS")
    }

    static func resolveStore() -> FountainStoreClient {
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

// MARK: - Prompts
private let creationPrompt = """
Scene: PatchBay Test Scene — Baseline (Host Graph + Visuals)
Text:

- Identity
  • Host (canvas): “PatchBay Canvas” — owns graph edges (“noodles”) and routing.
  • Instruments: “Fountain Editor”, “Corpus Instrument”, “LLM Adapter”.
  • Transform: “Submit” (text→baseline).

- Window & Layout (mac)
  • Window: 1440×900 pt, background #FAFBFD.
  • Panes: three vertical scroll panes with draggable gutters (6 pt).
    – Left: width ≈ 22% (min 160 pt); contains Fountain Editor (A4 typewriter).
    – Center: canvas fills remaining; renders grid and Flow overlay (nodes + noodles).
    – Right: width ≈ 26% (min 160 pt); monitor/log list, PE snapshots.
  • Gutters: horizontal drag; pane widths clamp to ≥160 pt.

- Center Canvas (Grid + Transform)
  • Grid: minor 24 pt, major every 5; axes at doc origin; left/top contact at view (0,0).
  • Transform defaults: zoom=1.00, translation=(0,0).

- Flow Overlay (Host‑Owned Visuals)
  • Node cards: 120×40 pt, r=6, fill #FFFFFF, stroke #E6EAF2, shadow rgba(0,0,0,0.06) 0 1 3; title system 12 pt.
  • Ports: inputs left, outputs right; 6 pt dots; input #7D8FB3, output #4C6BF5; hover +20%; selection ring #4C6BF5.
  • Noodles: cubic Bezier, stroke #6B8AF7 width 2 pt; selected #4C6BF5 width 3 pt; noodles below nodes by default.
  • Canonical positions (doc): Editor(100,100), Submit(380,120), Corpus(640,100), LLM(640,280); no drag in test scene.

- Canonical Edges
  • e-editor-submit: Editor.text.content.out → Submit → Corpus.baseline.add.in
  • e-editor-llm: Editor.text.content.out → LLM.prompt.in

- Left Pane (Editor)
  • A4 placeholder 595×842 pt; Courier Prime 12 pt; line-height 1.10; tabs→4 spaces; hard breaks only; empty hint “Click to start typing…”.

- Right Pane (Monitor)
  • Last 5 events (host: [HOST], instruments: [INST:Name]) at 12 pt.

- Protocol (Host)
  • flow.node.add/remove, flow.port.define, flow.edge.create/delete, flow.forward.test; target “PatchBay Canvas”.
  • Host PE: flow.nodes[], flow.edges[], routing.enabled (0/1).
  • Host monitors: flow.edge.created, flow.edge.deleted, flow.forwarded {count}.

- Instruments (reference)
  • Editor: text.set, editor.submit; PE wrap.column ∈ [58..62].
  • Corpus: corpus.baseline.add; PE counters & latest ids.
  • LLM: llm.chat; PE last.answer, last.function.name.

- Persistence (FountainStore; baseline-patchbay)
  • Page: scene:patchbay-test; Segments: teatro, script.fountain, graph, playbook.json, facts.
"""

private let mrtsPrompt = """
Scene: PatchBay Test Scene — MRTS (Visual + Routing)
Text:

- Objective
  • Validate visuals (layout + overlay) and routing via host‑owned Flow.

- Snapshot sizes
  • 1440×900 pt and 1280×800 pt; zoom=1.00; translation=(0,0); golden baselines for both.

- Steps (targets)
  1) Host PE SET layout.left.frac≈0.22, layout.right.frac≈0.26; assert gutters and min widths.
  2) Host flow.node.add: Editor, Submit, Corpus, LLM.
  3) Host flow.edge.create: e-editor-submit and e-editor-llm.
  4) Snapshot (1440×900): assert node rects at exact coordinates and noodles curvature.
  5) Editor.text.set sample + newline; expect text.parsed with wrapColumn ∈ [58..62].
  6) Editor.editor.submit; expect [HOST] flow.forwarded count ≥ 2, [INST:Corpus] corpus.baseline.added, [INST:LLM] llm.chat.started/completed.
  7) Snapshot again; assert no drift; overlays unchanged.
  8) Optional: Host flow.edge.delete e-editor-llm; assert [HOST] flow.edge.deleted and PE flow.edges decreased; snapshot reflects noodle removal.

- Visual invariants
  • Node rects (x,y,w,h) within ±0.5 pt; grid left/top contact pinned; noodles #6B8AF7; ports input #7D8FB3 / output #4C6BF5.

- Routing invariants
  • flow.forwarded.count ≥ 2; Corpus: baselines.total ≥ 1; LLM: last.answer non-empty.

- Where
  • Host target “PatchBay Canvas”; instruments address their display names; store under baseline-patchbay.
"""
