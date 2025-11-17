import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct FountainGUIDemoSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        let corpusId = env["CORPUS_ID"] ?? "fountain-gui-demo"
        let store = resolveStore()
        do {
            _ = try await store.createCorpus(corpusId, metadata: ["app": "fountain-gui-demo", "kind": "teatro+instrument"])
        } catch {
            // ignore if already exists
        }

        let pageId = "prompt:fountain-gui-demo"
        let page = Page(
            corpusId: corpusId,
            pageId: pageId,
            url: "store://prompt/fountain-gui-demo",
            host: "store",
            title: "FountainGUIKit Demo — Teatro Prompt"
        )
        _ = try? await store.addPage(page)
        let creation = creationPrompt()
        _ = try? await store.addSegment(.init(
            corpusId: corpusId,
            segmentId: "\(pageId):teatro",
            pageId: pageId,
            kind: "teatro.prompt",
            text: creation
        ))

        // Facts segment: describe instruments/properties/invariants in JSON for quick inspection.
        let facts: [String: Any] = [
            "instruments": [[
                "id": "canvas",
                "manufacturer": "Fountain",
                "product": "FountainGUIDemo",
                "instanceId": "fountain-gui-demo-1",
                "displayName": "FountainGUI Demo Canvas",
                "pe": [
                    "canvas.zoom",
                    "canvas.translation.x",
                    "canvas.translation.y",
                    "canvas.rotation"
                ]
            ]],
            "properties": [
                "canvas.zoom": [
                    "type": "float",
                    "min": 0.2,
                    "max": 5.0,
                    "default": 1.0
                ],
                "canvas.translation.x": [
                    "type": "float",
                    "min": -1000.0,
                    "max": 1000.0,
                    "default": 0.0
                ],
                "canvas.translation.y": [
                    "type": "float",
                    "min": -1000.0,
                    "max": 1000.0,
                    "default": 0.0
                ],
                "canvas.rotation": [
                    "type": "float",
                    "min": -6.283185307,
                    "max": 6.283185307,
                    "default": 0.0
                ]
            ],
            "invariants": [
                "Drag or scroll moves the square in the direction of motion (follow-finger pan).",
                "Pinch magnify scales the square around the canvas center; zoom stays within [0.2, 5.0].",
                "Rotate gesture rotates the square; rotation stays within [-2π, 2π].",
                "Arrow keys pan in fixed 20pt steps; +/- zoom in 10% steps; [/] rotate in 15° steps.",
                "All interactions are instantaneous; no easing or momentum in this demo."
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(
                corpusId: corpusId,
                segmentId: "\(pageId):facts",
                pageId: pageId,
                kind: "facts",
                text: json
            ))
        }

        print("Seeded FountainGUI demo prompt → corpus=\(corpusId) page=\(pageId)")
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else {
                url = URL(fileURLWithPath: dir, isDirectory: true)
            }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                return FountainStoreClient(client: disk)
            }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    static func creationPrompt() -> String {
        return """
        Scene: FountainGUI Demo — Minimal Canvas Instrument

        Text:
        - Window: macOS titlebar, 640×400 pt. Single canvas fills the content area; no sidebars or controls.
        - Canvas: light window background; a single solid blue square sits at the logical origin of the canvas transform.
        - Transform degrees of freedom:
          • canvas.zoom: scalar zoom factor applied uniformly in X and Y (default 1.0).
          • canvas.translation.x / canvas.translation.y: translation of the square in view points.
          • canvas.rotation: rotation of the square in radians around the canvas center.

        Interaction (pointer + trackpad):
        - Mouse drag (primary button) anywhere on the canvas pans the square (follow-finger): view-space deltas map directly into canvas.translation.{x,y}.
        - Two-finger scroll performs the same pan as drag; no momentum or acceleration in this demo.
        - Pinch (magnify) gesture scales canvas.zoom multiplicatively around the canvas center; zoom is clamped to [0.2, 5.0].
        - Rotate gesture adjusts canvas.rotation; rotation is clamped to [-2π, 2π] and applied about the canvas center.

        Interaction (keyboard fallback):
        - Arrow keys pan by fixed steps: 20 pt left/right/up/down by changing canvas.translation.{x,y}.
        - + / = keys zoom in by 10%; - / _ zoom out by 10%; both respect the same [0.2, 5.0] clamp.
        - [ and ] rotate by ±15° per keypress, within the same [-2π, 2π] range.

        Behaviour:
        - All interactions update the transform immediately; there is no easing, spring, or momentum in this demo.
        - The blue square remains axis-aligned in its own local space; only the canvas transform rotates it.
        - On launch, the canvas is centered, zoom = 1.0, translation = (0,0), rotation = 0.

        Property Exchange surface:
        - Properties exposed for instruments and tests:
          • canvas.zoom
          • canvas.translation.x
          • canvas.translation.y
          • canvas.rotation
        - These properties are surfaced both via the demo’s own HTTP spec (fountain-gui-demo.yml) and via the generic metalviewkit-runtime InstrumentState API.
        """
    }
}

