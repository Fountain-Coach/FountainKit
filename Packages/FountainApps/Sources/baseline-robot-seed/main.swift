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
                "RightEdgeContactTests"
            ],
            "pe": ["grid.minor","grid.majorEvery","zoom","translation.x","translation.y"],
            "vendorJSON": ["ui.panBy","ui.zoomAround","canvas.reset"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]), let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: json))
        }
        print("Seeded MRTS prompt → corpus=\(corpusId) pageId=\(pageId)")
    }

    static func teatroPrompt() -> String {
        return """
        Scene: Baseline‑PatchBay — MIDI Robot Test Script (MRTS)
        Text:
        - Objective: create a one‑shot runner that executes the baseline robot/invariant test subset against the Baseline‑PatchBay UI (grid‑only, instrument‑first).
        - Output: write a shell script at `Scripts/ci/baseline-robot.sh` (executable) that:
          • Builds the baseline UI product `baseline-patchbay` (grid-dev-app target).
          • Runs the robot/invariant test subset in `Packages/FountainApps/Tests/PatchBayAppUITests`:
            `GridInstrumentTests`, `ViewportGridContactTests`, `PixelGridVerifierTests`,
            `MIDIMonitorEventsTests`, `CanvasDefaultTransformTests`, `RightEdgeContactTests`.
          • Uses `ROBOT_ONLY=1` and `-Xswiftc -DROBOT_ONLY` to keep the surface minimal; exits non‑fatally if tests fail so artifacts can be inspected.

        Instruments (loopback transport in tests):
        - Canvas: { manufacturer: Fountain, product: GridDev, instanceId: grid-dev-1, displayName: "Grid Dev" }
        - Grid: { manufacturer: Fountain, product: Grid, instanceId: grid-1, displayName: "Grid" }
        - Viewport: { manufacturer: Fountain, product: Viewport, instanceId: viewport, displayName: "Right Pane" }

        Numeric invariants:
        - Default transform: zoom=1.0, translation=(0,0).
        - Left grid contact pinned at view.x=0 across translations/zoom.
        - Minor spacing px = grid.minor × zoom; major spacing = grid.minor × majorEvery × zoom.
        - Anchor‑stable zoom: drift ≤ 1 px.
        - Right edge contact: floor(view.width / (grid.minor × zoom)) and view.x = index × step.
        - Monitor emits `ui.zoom`/`ui.pan` (and debug variants) on zoomAround/pan/reset.

        Ops/PE (reference):
        - Vendor JSON: `ui.panBy {dx.view, dy.view}`, `ui.zoomAround {anchor.view.x, anchor.view.y, magnification}`, `canvas.reset`.
        - PE SET (SysEx7/CI): `grid.minor`, `grid.majorEvery`, `zoom`, `translation.x`, `translation.y`.
        """
    }
}

