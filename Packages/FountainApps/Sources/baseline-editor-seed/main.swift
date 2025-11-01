import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct BaselineEditorSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let store = resolveStore()

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+editor"]) } catch { }

        // Creation prompt page (mirror of fountain-editor-seed)
        let creationId = "prompt:fountain-editor"
        let creationPage = Page(corpusId: corpusId, pageId: creationId, url: "store://prompt/fountain-editor", host: "store", title: "Fountain Editor — A4 Typewriter (Creation)")
        _ = try? await store.addPage(creationPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(creationId):teatro", pageId: creationId, kind: "teatro.prompt", text: creationPrompt))

        // MRTS page (mirror)
        let mrtsId = "prompt:fountain-editor-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/fountain-editor-mrts", host: "store", title: "Fountain Editor — A4 Typewriter (MRTS)")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))
        if let facts = factsJSON { _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):facts", pageId: mrtsId, kind: "facts", text: facts)) }

        print("Seeded baseline editor prompts → corpus=\(corpusId) pages=[\(creationId), \(mrtsId)]")
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

    static let creationPrompt = FountainEditorSeedStrings.creation
    static let mrtsPrompt = FountainEditorSeedStrings.mrts
    static let factsJSON = FountainEditorSeedStrings.facts
}

// Copy of the strings used by fountain-editor-seed to avoid cross-target imports.
enum FountainEditorSeedStrings {
    static let creation = """
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
      • editor.submit { text, cursor? } — forward normalized content; host routes via PatchBay Graph to Corpus.
    - Flow Ports (typed wiring): outputs text.parsed.out (kind:text), text.content.out (kind:text).
    - Monitor/CI Events: "text.parsed", "suggestion.queued", "suggestion.applied", "memory.slots.updated", "awareness.synced".
    """
    static let mrts = """
    Scene: Fountain Editor — A4 Typewriter (MRTS)
    Text:
    - Objective: Validate typing + agent suggestions + semantic memory slots under A4 metrics with deterministic snapshots.
    - Steps: Reset + A4; Typing baseline; Agent suggest+apply; memory.inject; promote memory→suggestion; overlays toggle.
    - Invariants: Snapshot latency ≤ 300ms; wrap.column ∈ [58..62]; ~55±2 lines/page; types present; lifecycle events emitted.
    """
    static let facts = """
    {"robot":{"tests":["FountainEditorPEAndParseTests","FountainEditorVendorOpsTests"]}}
    """
}

