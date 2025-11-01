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
                "pe": [
                    "grid.minor", "grid.majorEvery", "zoom", "translation.x", "translation.y",
                    "layout.left.frac", "layout.right.frac"
                ],
                "vendorJSON": ["ui.panBy", "ui.zoomAround", "canvas.reset"]
            ]],
            "robot": [
                "subset": [
                    "ViewportGridContactTests", "GridInstrumentTests", "CanvasDefaultTransformTests", "MIDIMonitorEventsTests"
                ],
                "invariants": [
                    "leftGridContactPinnedAt0",
                    "majorSpacingPixels = minor*majorEvery*zoom",
                    "paneMinimumWidths >= 160pt",
                    "ui.layout.changed emits on gutter/PE",
                    "ui.dnd.begin/drop emit on drag-and-drop"
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
        Scene: GridDevApp — Three‑Pane Baseline (Editor Left, Canvas Center)
        Text:
        - Window: macOS titlebar window, 1440×900 pt; content background #FAFBFD.
        - Layout: three vertical scroll panes with draggable borders (gutters 6 pt):
          • Left Pane (scrollable): “Fountain Editor” (A4 typewriter) at top, then list scaffold. Default width ≈ 22% (min 160 pt).
          • Center Pane: “Grid” canvas instrument (fills center).
          • Right Pane (scrollable): monitor/log scaffold. Default width ≈ 26% (min 160 pt).
          • Gutters draggable horizontally; widths clamp to ≥160 pt; proportions persist during resize.
        - Canvas (center): Baseline grid instrument with viewport‑anchored grid (left contact at view.x=0, top at view.y=0), minor=24 pt, majorEvery=5, axes at doc origin.
        - Fountain Editor (left): A4 typewriter (Courier Prime 12pt, 1.10 line height, tabs→4 spaces, hard line breaks). Initial view shows an A4 empty page placed on a clean desktop. Typing sends `text.set {text,cursor}` and emits `text.parsed` with lines/chars/wrapColumn/page.
        - MIDI overlay: monitor/controls fade after inactivity; wake on MIDI activity.
        - Drag & Drop: items can be dragged between left/right panes; center accepts drops and logs events (no reflow).
        - Property Exchange (PE): layout.left.frac, layout.right.frac (0..1) adjust pane fractions and emit `ui.layout.changed`. Base PE: grid.minor, grid.majorEvery, zoom, translation.x, translation.y.

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
        - Suites: ViewportGridContactTests (left contact pinned), GridInstrumentTests (PE), CanvasDefaultTransformTests (defaults), MIDIMonitorEventsTests (ui.zoom/ui.pan emissions).
        - Invariants: leftGridContactPinnedAt0; pixelMajorSpacing = minor×majorEvery×zoom; ui.layout.changed posts on adjustments; DnD emits begin/drop.
        """
    }
}
