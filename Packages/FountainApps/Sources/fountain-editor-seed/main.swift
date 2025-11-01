import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct FountainEditorSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "fountain-editor"
        let store = resolveStore()

        // Ensure corpus
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "fountain-editor", "kind": "teatro+mrts"]) } catch { /* ignore if exists */ }

        // Creation prompt page
        let creationId = "prompt:fountain-editor"
        let creationPage = Page(corpusId: corpusId, pageId: creationId, url: "store://prompt/fountain-editor", host: "store", title: "Fountain Editor — A4 Typewriter (Creation)")
        _ = try? await store.addPage(creationPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(creationId):teatro", pageId: creationId, kind: "teatro.prompt", text: creationPrompt))

        // MRTS prompt page + facts
        let mrtsId = "prompt:fountain-editor-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/fountain-editor-mrts", host: "store", title: "Fountain Editor — A4 Typewriter (MRTS)")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):facts", pageId: mrtsId, kind: "facts", text: factsJSON))

        print("seeded fountain-editor prompts → corpusId=\(corpusId) pages=[\(creationId), \(mrtsId)]")
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    // MARK: - Prompts
    static let creationPrompt = """
    Scene: Fountain Editor — A4 Typewriter (Instrument)
    Text:
    - Identity: { manufacturer: Fountain, product: FountainEditor, displayName: "Fountain Editor", instanceId: "fountain-editor-1" }.
    - Page model (A4): 210×297 mm; margins L/R/T/B = 35/20/25/25 mm; paper centered on #FAFAFA with subtle shadow.
    - Typewriter feel: Courier Prime 12 pt (mono), line-height 1.10, ragged right; tabs→4 spaces; hard line breaks only; target wrap.column ∈ [58..62]; ~55±2 lines per page.
    - Sources (inputs):
      • Typing (primary): local edits to text.content.
      • LLM Agent: streaming deltas and suggestions; appears as queued suggestions with accept/apply.
      • Semantic Memory (Awareness): slots pane with read‑only cards for Drifts, Patterns, Reflections, History, Semantic Arcs; cards can be promoted into suggestions.
    - Property Exchange (PE):
      • text.content (string), cursor.index (int), cursor.select.start/end (int)
      • page.size ("A4"), page.margins.top/left/right/bottom (mm), font.name ("Courier Prime"), font.size.pt (12), line.height.em (1.10)
      • wrap.column (int; read‑only), parse.auto (0/1; default 1), parse.snapshot (write‑only; triggers notify)
      • awareness.corpusId (string; active corpus; mirrors Corpus Instrument `corpus.id`)
      • suggestions.count (int; R/O), suggestions.active.id (string?), overlays.show.{drifts,patterns,reflections,history,arcs} (0/1)
      • memory.counts.{drifts,patterns,reflections,history,arcs} (ints; R/O)
      • roles.enabled (0/1), roles.available[] (strings; R/O), roles.active (string)
    - Vendor JSON (SysEx7 UMP):
      • text.set { text, cursor? }, text.insert { text }, text.replace { start, end, text }, text.clear {}
      • agent.delta { text, id? }, agent.suggest { id, text, policy:"insertAt|append|replace", cursor? }, suggestion.apply { id }
      • awareness.setCorpus { corpusId }, awareness.refresh { kinds?:[drifts,patterns,reflections,history,arcs] }
      • memory.inject.{drifts|patterns|reflections|history|arcs} { items:[{ id, text, anchors?, meta? }] }, memory.promote { slot, id, policy, cursor? }
      • role.suggest { role, id, text, policy, cursor? }
      • editor.submit { text, cursor? } — forward normalized content to Corpus Instrument baseline.add under the active corpus/page context.
    - Flow Ports (typed wiring):
      • outputs: text.parsed.out (kind:text), text.content.out (kind:text)
      • routing: if a Flow graph is present and connected from an Editor output to a compatible input/Submit transform, editor.submit forwards via Flow; otherwise it falls back to Corpus baseline.add directly.
    - Monitor/CI Events:
      • "text.parsed" { nodes, lines, chars, types{…}, wrapColumn, page{…} }
      • "suggestion.queued" { id, source:"agent"|"role:<name>"|"memory:<slot>", policy, len }
      • "suggestion.applied" { id, deltaChars, newChars, newLines }
      • "memory.slots.updated" { counts:{ drifts,patterns,reflections,history,arcs } }
      • "awareness.synced" { corpusId }
    """

    static let mrtsPrompt = """
    Scene: Fountain Editor — A4 Typewriter (MRTS)
    Text:
    - Objective: Validate typing + agent suggestions + semantic memory slots under A4 metrics with deterministic snapshots.
    - Sample:
      INT. ROOM — DAY\nJOHN\n(whispering)\nHello.\nHe sits.\n
    Steps:
    1) Reset + A4: PE SET text.content="", cursor.index=0, page.size="A4", margins(35/20/25/25), font, lineHeight; parse.snapshot=1. Expect lines=0, chars=0, nodes=0; wrap.column∈[58..62].
    2) Typing baseline: PE SET text.content=<sample>; parse.snapshot=1. Expect types include sceneHeading≥1, character≥1, parenthetical≥1, dialogue≥1, action≥1; lines=5; nodes≥5.
    3) Agent suggestion: agent.suggest { id:"s1", text:"\nCUT TO:", policy:"append" } → suggestion.queued; suggestion.apply { id:"s1" }; parse.snapshot=1 → transition≥1.
    4) Memory slots: memory.inject.* with ≥1 item each; expect memory.slots.updated counts and PE memory.counts.*.
    5) Promote memory→suggestion: role or memory card → suggestion; apply; parse.snapshot=1; assert chars/lines deltas.
    6) Overlays toggle: PE SET overlays.show.arcs=1, overlays.show.drifts=1; expect overlays change (no text change).

    Invariants:
    - Snapshot latency ≤ 300 ms; wrap.column ∈ [58..62]; ~55±2 lines per A4 page.
    - Exact line/char counts; required types present for the sample.
    - suggestion.* lifecycle produces queued/applied events; memory counts track injections; awareness.synced posts on setCorpus/refresh.
    """

    static let factsJSON: String = {
        let facts: [String: Any] = [
            "instrument": [
                "manufacturer": "Fountain",
                "product": "FountainEditor",
                "displayName": "Fountain Editor",
                "pe": [
                    "text.content","cursor.index","cursor.select.start","cursor.select.end",
                    "page.size","page.margins.top","page.margins.left","page.margins.right","page.margins.bottom",
                    "font.name","font.size.pt","line.height.em","wrap.column","parse.auto","parse.snapshot",
                    "awareness.corpusId","suggestions.count","suggestions.active.id",
                    "overlays.show.drifts","overlays.show.patterns","overlays.show.reflections","overlays.show.history","overlays.show.arcs",
                    "memory.counts.drifts","memory.counts.patterns","memory.counts.reflections","memory.counts.history","memory.counts.arcs",
                "roles.enabled","roles.available","roles.active"
            ],
            "vendorJSON": [
                "text.set","text.insert","text.replace","text.clear",
                "agent.delta","agent.suggest","suggestion.apply",
                "awareness.setCorpus","awareness.refresh",
                "memory.inject.drifts","memory.inject.patterns","memory.inject.reflections","memory.inject.history","memory.inject.arcs","memory.promote",
                "role.suggest",
                "editor.submit"
            ],
            "ports": [
                "outputs": [
                    ["id": "text.parsed.out", "kind": "text"],
                    ["id": "text.content.out", "kind": "text"]
                ]
            ]
        ],
            "robot": [
                "tests": ["FountainEditorPEAndParseTests","FountainEditorVendorOpsTests"],
                "invariants": [
                    "snapshotLatency<=300ms","wrapColumnIn58..62","linesPerPage≈55±2",
                    "lineCountExact","charCountExact",
                    "typesContain(sceneHeading,character,parenthetical,dialogue,action)"
                ],
                "sample": "INT. ROOM — DAY\nJOHN\n(whispering)\nHello.\nHe sits.\n"
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }()
}
