import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct QuietFrameCompanionSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "quietframe-companion"
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

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "quietframe-companion", "kind": "teatro+pe"]) } catch { }

        // Creation prompt
        let pageId = "prompt:quietframe-companion"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://prompt/quietframe-companion", host: "store", title: "Quiet Frame Companion — PE Inspector"))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))

        // Facts JSON
        if let facts = factsJSON() {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts))
        }

        // MRTS prompt
        let mrtsId = "prompt:quietframe-companion-mrts"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/quietframe-companion-mrts", host: "store", title: "Quiet Frame Companion — MRTS"))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))
        await seedRefs(store, corpusId: corpusId)
        print("Seeded Quiet Frame Companion prompts + refs → corpus=\(corpusId) pages=[\(pageId), prompt:quietframe-companion-mrts, docs:quietframe:act1:refs]")
    }

    static let creationPrompt = """
    Scene: Quiet Frame Companion — Param Controller for Sonify (OpenAPI‑first, PE bridge)

    What
    - A compact control surface for Quiet Frame Sonify. Talks to the Sidecar Params service to GET/LIST/PATCH parameters and subscribes to the SSE stream to mirror live state across apps. Exposes grouped controls (Engine, Drone, Clock, Breath, Overtones, FX, Act).
    - OpenAPI Params is primary; Sidecar bridges to MIDI‑CI PE for compatibility. MIDI 1.0 CC on “Quiet Frame M1” is a coarse fallback. Preset save/load via OpenAPI (and vendor JSON fallback).

    Why
    - Tune sound parameters live from a reliable companion; capture/apply presets deterministically; accelerate testing.

    How
    - On launch: connect to Sidecar; GET /v1/params to build UI with ranges from Facts; subscribe `/v1/params/stream` for mirroring; bind controls to `PATCH /v1/params` (50–100 ms debounce).
    - PE bridge: when OpenAPI is unavailable, fall back to PE (GET/SET/Notify) to keep the test surface operable. CC fallback (Ch.1) remains as a last resort.
    """

    static let mrtsPrompt = """
    Scene: Quiet Frame Companion — MRTS (OpenAPI Params + PE Bridge)

    Steps
    - Connect to Sidecar → GET /v1/params returns properties (>= 24), no error.
    - Engine Master: 0.8 → 0.5 via PATCH → audible drop on Sonify; SSE pushes 0.5.
    - Drone LPF sweep 1200→4000 Hz → Sonify brightens; frequency map within ±2%.
    - Mute toggle → silence; Panic → All Notes Off; Sonify engine remains running.
    - Preset roundtrip: POST preset; modify 3 controls; apply preset → sound + SSE revert.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "targets": [[
                "id": "quietframe",
                "endpoint2": "Quiet Frame",
                "endpoint1": "Quiet Frame M1",
                "channel1": 1
            ]],
            "openapi": [
                "baseURL": "http://127.0.0.1:7777",
                "params": [
                    "GET /v1/params",
                    "PATCH /v1/params",
                    "GET /v1/params/stream"],
                "presets": [
                    "GET /v1/presets",
                    "POST /v1/presets",
                    "POST /v1/presets/{name}/apply"]
            ],
            "pe.buckets": [
                ["name":"Engine",    "props":["engine.masterGain","audio.muted"]],
                ["name":"Drone",     "props":["drone.amp","drone.lpfHz","drone.reso","drone.detune","drone.mixSaw"]],
                ["name":"Clock",     "props":["clock.level","clock.div","clock.ghostProbability"]],
                ["name":"Breath",    "props":["breath.level","breath.centerHz","breath.width"]],
                ["name":"Overtones", "props":["overtones.mix","overtones.modIndex","overtones.chorus"]],
                ["name":"FX",        "props":["fx.plate.mix","fx.delay.mix","fx.delay.feedback","fx.limiter.threshold"]],
                ["name":"Act",       "props":["act.section","tempo.bpm","harmony.key","harmony.scale"]]
            ],
            "vendorJSON": ["audio.test.ping","preset.save","preset.load","act.set","tempo.set","harmony.set"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }

    // Optional: add cross-references for Act I and reviews page pointers
    static func seedRefs(_ store: FountainStoreClient, corpusId: String) async {
        let pageId = "docs:quietframe:act1:refs"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://docs/quietframe/act1/refs", host: "store", title: "QuietFrame — References (Act I)"))
        let refs = [
            ["ref": "store://docs/quietframe/act1#die-maschine-traeumt", "corpus": "quietframe-sonify"],
            ["ref": "store://docs/quietframe/act1#quietframe-note", "corpus": "quietframe-sonify"],
            ["ref": "store://reviews/quietframe/act2/cell-collider#index", "corpus": "quietframe-sonify"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: refs, options: [.prettyPrinted]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):index", pageId: pageId, kind: "refs", text: text))
        }
    }
}
