import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PatchbayGraphSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        // Baseline corpus for mac app
        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url: URL
                if dir.hasPrefix("~") {
                    url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
                } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+graph-protocol"]) } catch { }

        let pageId = "prompt:patchbay-graph"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/patchbay-graph", host: "store", title: "PatchBay Host — Graph Protocol (Creation)")
        _ = try? await store.addPage(page)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))
        if let facts = factsJSON() { _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts)) }

        let mrtsId = "prompt:patchbay-graph-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/patchbay-graph-mrts", host: "store", title: "PatchBay Graph — MRTS")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))

        // Seed a default graph (Editor → Submit → Corpus, Editor → LLM)
        await seedDefaultGraph(store: store, corpusId: corpusId)
        print("Seeded PatchBay Graph prompts → corpus=\(corpusId) pages=[\(pageId), \(mrtsId)] + default graph")
    }

    static let creationPrompt = """
    Scene: PatchBay Host — Graph Protocol (Ports, Noodles, Routing)
    Text:
    - Ownership: The PatchBay host (canvas) owns the visual/semantic graph that connects instruments. Instruments own ports; the host owns edges (noodles) and routing.
    - Visual: Nodes (instruments/transforms) and noodles render over the center canvas; selection highlights ports/edges; inspectors show instrument PE and recent monitors.
    - Protocol (MIDI 2.0, SysEx7 vendor JSON; target = "PatchBay Canvas"):
      • flow.node.add { nodeId, displayName, product }
      • flow.node.remove { nodeId }
      • flow.port.define { nodeId, portId, dir:in|out, kind }
      • flow.edge.create { from:{node,port}, to:{node,port}, transformId? }
      • flow.edge.delete { edgeId }
      • flow.forward.test { from:{node|displayName,port}, payload:{ kind, … } }
    - Routing: Host delivers events to destination input ports; transform nodes (e.g., Submit) perform simple coercions (text→baseline) before forwarding.
    - Monitor (host): "flow.edge.created", "flow.edge.deleted", "flow.forwarded" { count }. Instruments emit their own monitors (e.g., corpus.baseline.added, llm.chat.*).
    - PE (host): flow.nodes[], flow.edges[], selected.nodeId?, selected.edgeId?, routing.enabled (0/1), autosave (0/1).
    - Persistence: Page `prompt:patchbay-graph` with segments: graph.json (nodes/edges), facts (portKinds, known transforms).
    - Compatibility: Previous “Flow Instrument” is deprecated; behavior subsumed by the host protocol.
    """

    static let mrtsPrompt = """
    Scene: PatchBay Graph — MRTS: Host Protocol
    Text:
    - Objective: Verify host graph wiring and forwarding between Editor, Corpus, and LLM.
    - Steps (target = "PatchBay Canvas"):
      1) flow.node.add Editor, Corpus, Submit, LLMAdapter (auto-ports for known products allowed).
      2) flow.edge.create: Editor.text.content.out → Submit → Corpus.baseline.add.in.
      3) flow.edge.create: Editor.text.content.out → LLMAdapter.prompt.in.
      4) flow.forward.test from Editor.text.content.out with payload {kind:text,text:"Hello"}.
      5) Expect flow.forwarded; expect corpus.baseline.added and llm.chat.started/completed monitors.
      6) flow.edge.delete any; expect flow.edge.deleted and PE reflects change.
    - Invariants: type-safe wiring; forwarding count ≥ 1; PE hosts flow.nodes/flow.edges; persistence: graph.json present.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "host": [
                "product": "PatchBay",
                "canvas": "PatchBay Canvas",
                "pe": ["flow.nodes","flow.edges","selected.nodeId","selected.edgeId","routing.enabled","autosave"],
                "vendorJSON": ["flow.node.add","flow.node.remove","flow.port.define","flow.edge.create","flow.edge.delete","flow.forward.test"],
                "portKinds": ["text","baseline","drift","patterns","reflection","json","pe-snapshot"],
                "transforms": ["Submit(text→baseline)","ComputeDrift","ComputePatterns","ComputeReflection"],
                "deprecated": ["Flow Instrument"]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }

    static func seedDefaultGraph(store: FountainStoreClient, corpusId: String) async {
        let pageId = "prompt:patchbay-graph"
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

