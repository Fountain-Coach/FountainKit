import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct BaselineRobotSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
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
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
                return FountainStoreClient(client: disk)
            }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        // Ensure corpus exists
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+robot-tests"]) } catch { /* ignore if exists */ }

        let pageId = "prompt:baseline-robot-mrts"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/baseline-robot-mrts", host: "store", title: "Baseline‑PatchBay — MIDI Robot Test Script (MRTS)")
        _ = try? await store.addPage(page)

        let prompt = teatroPrompt()
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: prompt))

        let facts: [String: Any] = [
            "product": "baseline-patchbay",
            "targets": ["grid-dev-app"],
            "scripts": [
                "Scripts/ci/baseline-robot.sh"
            ],
            "tests": [
                "GridInstrumentTests",
                "ViewportGridContactTests",
                "PixelGridVerifierTests",
                "MIDIMonitorEventsTests",
                "CanvasDefaultTransformTests",
                "RightEdgeContactTests",
                "TrackpadGestureTests"
            ],
            "pe": [
                "grid.minor","grid.majorEvery","zoom","translation.x","translation.y",
                "layout.left.frac","layout.right.frac"
            ],
            "vendorJSON": ["ui.panBy","ui.zoomAround","canvas.reset"],
            "invariants": [
                "paneMinimumWidths >= 160pt",
                "ui.layout.changed emits on gutter/PE",
                "ui.dnd.begin/ui.dnd.drop during DnD",
                "leftGridContactPinnedAt0",
                "majorSpacingPixels = minor*majorEvery*zoom",
                "editor.textParsedEmitted"
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]), let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: json))
        }
        print("Seeded MRTS prompt → corpus=\(corpusId) pageId=\(pageId)")
    }

    static func teatroPrompt() -> String {
        return """
        Scene: Baseline‑PatchBay — MRTS: Three‑Pane Layout + Grid + Editor
        Text:
        - Objective: execute baseline robot tests against the three‑pane Baseline‑PatchBay (canvas+editor center) validating layout, DnD, grid invariants, and editor parsing.
        - Runner: `Scripts/ci/baseline-robot.sh` builds `baseline-patchbay` and runs a focused suite.
        - Steps:
          • Set `layout.left.frac=0.25`, `layout.right.frac=0.25` via PE; expect `ui.layout.changed`.
          • Resize window (+300 pt width); assert panes ≥160 pt, center ≥160 pt.
          • Drag left gutter +80 pt right; assert left fraction increased; event emitted.
          • Drag right gutter +100 pt right; assert right fraction decreased; event emitted.
          • Drag an item Left→Right; assert counts (+1/−1) and `ui.dnd.begin/drop`.
          • Drag an item Right→Left; assert counts (+1/−1) and `ui.dnd.begin/drop`.
          • Drop an item to Center; assert `ui.dnd.drop` with `target=center`.
          • Validate grid contact/spacing and anchor‑stable zoom drift ≤ 1 px.
          • Editor: `text.clear`; then `text.set` with 5‑line sample; expect `text.parsed` with lines=5 and wrapColumn ∈ [58..62]; apply `agent.suggest` + `suggestion.apply`; expect updated `text.parsed`.

        Instruments (loopback in tests):
        - Canvas: { manufacturer: Fountain, product: GridDev, instanceId: grid-dev-1, displayName: "Grid Dev" }
        - Viewport: { manufacturer: Fountain, product: Viewport, instanceId: viewport, displayName: "Right Pane" }

        Numeric invariants:
        - Pane mins: left/right/center ≥ 160 pt; gutters 6 pt; fractions clamp [0.05, 0.9].
        - Grid: left contact pinned; minor px = grid.minor × zoom; major px = grid.minor × majorEvery × zoom.
        - Monitor emits `ui.zoom(.debug)`/`ui.pan(.debug)`, `ui.layout.changed`, `ui.dnd.begin/drop`, and editor `text.parsed`.

        Ops/PE (reference):
        - Vendor JSON: `ui.panBy {dx.view, dy.view}`, `ui.zoomAround {anchor.view.x, anchor.view.y, magnification}`, `canvas.reset`.
        - PE SET: `grid.minor`, `grid.majorEvery`, `zoom`, `translation.x`, `translation.y`, `layout.left.frac`, `layout.right.frac`.
        """
    }
}
