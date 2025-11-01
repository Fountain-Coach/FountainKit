import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct CorpusInstrumentSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        // Use baseline-patchbay corpus by default so the baseline app can discover it easily
        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let pageId = "prompt:corpus-instrument"

        let store: FountainStoreClient = {
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
        }()

        // Ensure corpus and page exist
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+corpus-instrument"]) } catch { /* ignore if exists */ }
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/corpus-instrument", host: "store", title: "Corpus Instrument — Teatro Prompt")
        _ = try? await store.addPage(page)

        let prompt = teatroPrompt()
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: prompt))

        if let facts = factsJSON() {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts))
        }

        // Add MRTS page for Corpus Instrument
        let mrtsId = "prompt:corpus-instrument-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/corpus-instrument-mrts", host: "store", title: "Corpus Instrument — MRTS")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))

        print("Seeded Corpus Instrument prompt → corpus=\(corpusId) pageId=\(pageId)")
    }

    static func teatroPrompt() -> String {
        return """
        Scene: Corpus Instrument — FountainStore + Drift–Pattern–Reflection
        Text:
        - Identity: { manufacturer: Fountain, product: CorpusInstrument, displayName: "Corpus Instrument", instanceId: "corpus-1" }.
        - Role: Bridge editor and services to corpus memory. Normalize editor text into Baselines, compute Drift/Patterns/Reflection, and persist Analyses and pages/segments.
        - Active context:
          • corpus.id (string; required)
          • page.id (string; optional; prompt/page identifier sotto voce: "store://prompt/<id>" or upstream URL)
          • baseline.id (string?; current or last baseline identifier)
        - OpenAPI mapping (Persist v1):
          • list/create corpus: GET/POST /corpora
          • baselines: GET/POST /corpora/{corpusId}/baselines
          • analyses (per page): GET/POST /corpora/{corpusId}/analyses
          • pages/segments: stored via FountainStore client under /pages and /segments (in-process), or routed via service where applicable.
        - Outputs (monitor/notify):
          • "corpus.baseline.added" { corpusId, baselineId, chars, lines }
          • "corpus.drift.computed" { added, changed, removed }
          • "corpus.patterns.computed" { count }
          • "corpus.reflection.computed" { claims }
          • "corpus.analysis.indexed" { pageId, artifacts:[…] }
          • Each emit includes ts and a brief meta{…}, and persists a PE snapshot with last.op and ids.
        - Flow Ports (typed wiring):
          • Inputs: editor.submit.in (kind:text), baseline.add.in (kind:baseline), drift.compute.in (kind:baseline), patterns.compute.in (kind:drift), reflection.compute.in (kind:patterns)
          • Outputs: baseline.added.out (kind:baseline), drift.computed.out (kind:drift), patterns.computed.out (kind:patterns), reflection.computed.out (kind:reflection)
        - Inputs (editor and services) — Vendor JSON (SysEx7 UMP):
          • "editor.submit" { text, cursor? } → normalize → "corpus.baseline.add" (PE set or vendor operation)
          • "corpus.baseline.add" { text, pageId?, baselineId? } → POST /corpora/{corpusId}/baselines; emit "corpus.baseline.added"
          • "corpus.drift.compute" { sourceBaselineId?, targetBaselineId? } → compute Dₙ; store as analysis or segment; emit "corpus.drift.computed"
          • "corpus.patterns.compute" { upToBaselineId? } → cluster; emit "corpus.patterns.computed"
          • "corpus.reflection.compute" { driftId?, patternsId? } → reflect; emit "corpus.reflection.computed"
          • "corpus.analysis.index" { pageId, text?, assets? } → index anchors/segments; emit "corpus.analysis.indexed"
          • "corpus.page.upsert" { pageId, title?, url? } → upsert page doc in FountainStore
        - Property Exchange (PE):
          • corpus.id (R/W string), page.id (R/W string)
          • baseline.latest.id (R/O string), drift.latest.id (R/O string), patterns.latest.id (R/O string), reflection.latest.id (R/O string)
          • last.op (R/O string; enum: baseline.add|drift.compute|patterns.compute|reflection.compute|analysis.index|page.upsert)
          • last.ts (R/O ISO8601)
          • counters: baselines.total, analyses.total (R/O ints)
        - Normalization and invariants (editor → baseline):
          • Text normalization: tabs→4 spaces; preserve hard breaks; ensure trailing newline; metadata includes wrapColumn estimate from editor.
          • Lines = split by '\n' (don’t omit empty trailing).
          • Zero-length text → accepted as baseline with lines=0, chars=0.
        - Persisted artifacts:
          • Baselines: { baselineId, text, lines, chars, pageId?, wrapColumn? } stored under baselines.
          • Analyses: Drift/Patterns/Reflection stored as structured JSON (arrays of sentence-level Claims), keyed by { corpusId, pageId?, baselineId }.
        - Web constraints:
          • Stateless operations allowed; sessions derive from active PE (corpus.id/page.id). Targets default to the Corpus Instrument by displayName.
        """
    }

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "instrument": [
                "displayName": "Corpus Instrument",
                "product": "CorpusInstrument",
                "pe": [
                    "corpus.id","page.id","baseline.latest.id","drift.latest.id","patterns.latest.id","reflection.latest.id",
                    "last.op","last.ts","baselines.total","analyses.total"
                ],
                "vendorJSON": [
                    "editor.submit","corpus.baseline.add","corpus.drift.compute","corpus.patterns.compute",
                    "corpus.reflection.compute","corpus.analysis.index","corpus.page.upsert"
                ],
                "ports": [
                    "inputs": [
                        ["id": "editor.submit.in", "kind": "text"],
                        ["id": "baseline.add.in", "kind": "baseline"],
                        ["id": "drift.compute.in", "kind": "baseline"],
                        ["id": "patterns.compute.in", "kind": "drift"],
                        ["id": "reflection.compute.in", "kind": "patterns"]
                    ],
                    "outputs": [
                        ["id": "baseline.added.out", "kind": "baseline"],
                        ["id": "drift.computed.out", "kind": "drift"],
                        ["id": "patterns.computed.out", "kind": "patterns"],
                        ["id": "reflection.computed.out", "kind": "reflection"]
                    ]
                ]
            ],
            "openapi": [
                "persist": [
                    "GET /corpora","POST /corpora",
                    "GET /corpora/{corpusId}/baselines","POST /corpora/{corpusId}/baselines",
                    "GET /corpora/{corpusId}/analyses","POST /corpora/{corpusId}/analyses"
                ]
            ],
            "invariants": [
                "editor.submit→baseline.add recorded",
                "drift computes Added/Changed/Removed per spec",
                "patterns count 3..6",
                "reflection claims 4..7",
                "each op emits monitor event + PE snapshot"
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return nil
    }

    static let mrtsPrompt = """
    Scene: Corpus Instrument — MRTS: Baseline + Analyses
    Text:

    - Objective: Drive corpus baseline and analysis ops and assert monitor events and PE counters.
    - Steps (target = "Corpus Instrument"):
      1) corpus.baseline.add { text: "INT. ROOM — DAY\nHello." }
         • Expect monitor: corpus.baseline.added { baselineId, lines, chars }
         • PE: baseline.latest.id updated; baselines.total += 1; last.op = "baseline.add"
      2) corpus.drift.compute {}
         • Expect monitor: corpus.drift.computed {...}
         • PE: drift.latest.id updated; analyses.total += 1; last.op = "drift.compute"
      3) corpus.patterns.compute {}
         • Expect monitor: corpus.patterns.computed { count }
         • PE: patterns.latest.id updated; analyses.total += 1; last.op = "patterns.compute"
      4) corpus.reflection.compute {}
         • Expect monitor: corpus.reflection.computed { claims }
         • PE: reflection.latest.id updated; analyses.total += 1; last.op = "reflection.compute"
      5) corpus.analysis.index { pageId: "store://prompt/example" }
         • Expect monitor: corpus.analysis.indexed { pageId }
         • PE: analyses.total += 1; last.op = "analysis.index"

    - Invariants: baselines.total ≥ 1; analyses.total increases with each compute/index; latest ids non-empty after each step; monitors emitted per operation.
    """
}
