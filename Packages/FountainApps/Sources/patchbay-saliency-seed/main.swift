import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PatchbaySaliencySeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

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

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "patchbay-app", "kind": "teatro+scene"]) } catch { }

        let pageId = "prompt:patchbay-saliency"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/patchbay-saliency", host: "store", title: "PatchBay — Saliency + Csound + Ollama (Creation)")
        _ = try? await store.addPage(page)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))
        if let facts = factsJSON() { _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts)) }

        let mrtsId = "prompt:patchbay-saliency-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/patchbay-saliency-mrts", host: "store", title: "PatchBay — Saliency + Csound + Ollama (MRTS)")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))

        // Seed a matching default graph for convenience (QuietFrame → Csound; Chat separate)
        await seedGraph(store: store, corpusId: corpusId)
        print("Seeded PatchBay Saliency prompts → corpus=\(corpusId) pages=[\(pageId), \(mrtsId)] + default graph")
    }

    static let creationPrompt = """
    Scene: PatchBay — Saliency + Csound + Ollama
    What
    - Instruments on canvas: Quiet Frame (vision probe), Csound Sonifier (audio), LLM Chat (Ollama).
    - Data flow: cursor-over-QuietFrame computes a saliency scalar → drives Csound via MIDI 2.0 (CC1 + simple notes).
    - Chat pulses: streamed tokens from LLM emit llm.pulse events to animate noodles.

    Why
    - Demonstrate transport-agnostic instrumentation: vision probe → MIDI2 sonification; chat pulses visualize operator feedback.

    How
    - Quiet Frame: output port out (kind: saliency in [0..1]).
    - Csound Sonifier: input port in; maps saliency to CC1 and note selection.
    - Chat: prompt in, answer out; when streaming, emits llm.pulse for visual feedback.
    - MIDI 2.0: A dedicated “Csound Bridge” virtual endpoint sends UMP Note/CC.

    Where
    - Overlay + bridge wiring: Packages/FountainApps/Sources/patchbay-app/Saliency/*
    - Chat instrument window: Packages/FountainApps/Sources/patchbay-app/Chat/ChatInstrumentWindow.swift
    - Runner for Csound: Scripts/audiotalk/run-csound-saliency
    """

    static let mrtsPrompt = """
    Scene: PatchBay — Saliency + Csound + Ollama (MRTS)
    Text
    - Steps (target = "PatchBay Canvas"):
      1) Place Quiet Frame, Csound, Chat nodes.
      2) Simulate cursor movement over Quiet Frame center; expect CC1≈1.0 and an audible note (when Csound running).
      3) Move cursor to a corner; expect CC1≈0.0; previous note releases.
      4) Trigger llm.pulse; expect downstream noodles from Chat to glow briefly.
    - Numeric invariants: saliency monotonic with radial distance; CC1 maps 0..1; glow duration ≈0.5s.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "instruments": [
                ["id": "quietframe", "product": "saliency.quietFrame", "ports": [["id": "out", "dir": "out", "kind": "saliency"]]],
                ["id": "csound", "product": "csound.sonify", "ports": [["id": "in", "dir": "in", "kind": "saliency"]]],
                ["id": "chat", "product": "audiotalk.chat", "ports": [["id": "prompt", "dir": "in", "kind": "text"],["id": "answer", "dir": "out", "kind": "text"]]]
            ],
            "events": ["ui.cursor.move","llm.pulse"],
            "midi": ["Csound Bridge": ["cc1": "saliency", "note": "intensity→scale"]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }

    static func seedGraph(store: FountainStoreClient, corpusId: String) async {
        let pageId = "prompt:patchbay-saliency"
        let nodes: [[String: Any]] = [
            ["id": "quietframe", "displayName": "Quiet Frame", "product": "saliency.quietFrame", "x": 240, "y": 220],
            ["id": "csound", "displayName": "Csound", "product": "csound.sonify", "x": 240+12*24, "y": 220],
            ["id": "chat", "displayName": "LLM Chat", "product": "audiotalk.chat", "x": 240, "y": 220-7*24]
        ]
        let edges: [[String: Any]] = [
            ["id": "e-qf-csound", "from": ["node": "quietframe", "port": "out"], "to": ["node": "csound", "port": "in"]],
            ["id": "e-chat-csound", "from": ["node": "chat", "port": "answer"], "to": ["node": "csound", "port": "in"]]
        ]
        let graph: [String: Any] = ["nodes": nodes, "edges": edges]
        if let data = try? JSONSerialization.data(withJSONObject: graph, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):graph", pageId: pageId, kind: "graph.json", text: text))
        }
    }
}

