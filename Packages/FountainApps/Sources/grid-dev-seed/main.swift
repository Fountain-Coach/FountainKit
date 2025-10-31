import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct GridDevSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        let corpusId = env["CORPUS_ID"] ?? "grid-dev"
        let store = resolveStore()
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "grid-dev", "kind": "teatro+instruments"]) } catch { /* ignore */ }

        let pageId = "prompt:grid-dev"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/grid-dev", host: "store", title: "Grid Dev — Teatro Prompt")
        _ = try? await store.addPage(page)

        let prompt = teatroPrompt()
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: prompt))

        // Persist a small fact sheet capturing instrument identity and PE mapping
        let facts: [String: Any] = [
            "instruments": [[
                "manufacturer": "Fountain",
                "product": "GridDev",
                "instanceId": "grid-dev-1",
                "displayName": "Grid Dev",
                "pe": ["grid.minor", "grid.majorEvery", "zoom", "translation.x", "translation.y"],
                "vendorJSON": ["ui.panBy", "ui.zoomAround", "canvas.reset"]
            ]],
            "robot": [
                "subset": ["ViewportGridContactTests", "GridInstrumentTests", "CanvasDefaultTransformTests"],
                "invariants": [
                    "leftGridContactPinnedAt0",
                    "majorSpacingPixels = minor*majorEvery*zoom"
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]), let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: json))
        }

        print(prompt)
        print("\nseeded grid-dev prompt → corpusId=\(corpusId) pageId=\(pageId)")
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
        // Default to repo-local store like persist-server
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    static func teatroPrompt() -> String {
        return """
        Scene: GridDevApp (Grid‑Only with Persistent Corpus)
        Text:
        - Window: macOS titlebar window, 1440×900pt. Content background white (#FAFBFD).
        - Layout: single full‑bleed canvas; no sidebar, no extra panes, minimal chrome.
        - Only view: “Grid” Instrument filling the content.
          - Grid anchoring: viewport‑anchored. Leftmost vertical line renders at view.x = 0 across all translations/zoom. Topmost horizontal line at view.y = 0.
          - Minor spacing: 24 pt; Major every 5 minors (120 pt). Minor #ECEEF3, Major #D1D6E0. Crisp 1 px.
          - Axes: Doc‑anchored origin lines (x=0/y=0) in faint red (#BF3434) for orientation.
          - Overlay top‑left: “Zoom 1.00x  Origin (0, 0)” (SF Mono 11, capsule #EEF2F7, text #6B7280).
          - No nodes, edges, ports, selection.
        - MIDI 2.0 Identity (instrument): { manufacturer: Fountain, product: GridDev, displayName: "Grid Dev", instanceId: "grid-dev-1" }
        - Property Exchange (PE): floats/ints
          - grid.minor (Int, default 24)
          - grid.majorEvery (Int, default 5)
          - zoom (Float, default 1.0, clamp 0.1…8.0)
          - translation.x (Float, default 0)
          - translation.y (Float, default 0)
        - Vendor JSON ops (SysEx7 UMP):
          - ui.panBy {dx.doc, dy.doc} or {dx.view, dy.view}; convert view→doc via /zoom. Grid stays viewport‑anchored; axes reflect world movement.
          - ui.zoomAround {anchor.view.x, anchor.view.y, magnification}; anchor‑stable.
          - canvas.reset → zoom=1.0, tx=0, ty=0.
        - Visual rules:
          - Left contact point pinned: first vertical grid line renders at x=0.0±0.5 px at all transforms.
          - Major spacing in pixels = grid.minor × majorEvery × zoom.
        - Defaults at boot: zoom=1.0, translation=(0,0), grid.minor=24, grid.majorEvery=5.
        - Optional overlay on by default: “MIDI 2.0 Monitor” pinned to the top‑right, showing recent vendor JSON/PE events.

        Persistence — FountainStore (Corpus: grid-dev)
        - Create corpus id: grid-dev (metadata: {app: grid-dev, kind: teatro+instruments}).
        - Store Teatro prompt under:
          - pages: [ { pageId: "prompt:grid-dev", title: "Grid Dev — Teatro Prompt", url: "store://prompt/grid-dev" } ]
          - segments: [
              { segmentId: "prompt:grid-dev:teatro", pageId: "prompt:grid-dev", kind: "teatro.prompt", text: <this prompt> },
              { segmentId: "prompt:grid-dev:facts", pageId: "prompt:grid-dev", kind: "facts", text: {instruments, PE map, vendor ops, robot subset} }
            ]
        - Evidence (filesystem):
          - UMP logs → .fountain/corpus/ump/*.ndjson
          - Replay artifacts → .fountain/artifacts/replay/<log>/*.mov

        Robot testing (subset)
        - Suites: ViewportGridContactTests (left contact pinned), GridInstrumentTests (PE updates), CanvasDefaultTransformTests (startup defaults).
        - Invariants: leftGridContactPinnedAt0; pixelMajorSpacing = minor×majorEvery×zoom.
        """
    }
}
