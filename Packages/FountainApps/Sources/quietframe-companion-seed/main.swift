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

        print("Seeded Quiet Frame Companion prompts → corpus=\(corpusId) pages=[\(pageId), prompt:quietframe-companion-mrts]")
    }

    static let creationPrompt = """
    Scene: Quiet Frame Companion — PE Inspector for Sonify (Midified)

    What
    - A compact control surface for Quiet Frame Sonify. Discovers the “Quiet Frame” MIDI 2.0 endpoint, fetches PE properties, and exposes grouped controls (Engine, Drone, Clock, Breath, Overtones, FX, Act).
    - Uses MIDI 2.0 PE (GET/SET/snapshot) primarily; falls back to MIDI 1.0 CC on “Quiet Frame M1” for coarse control. Provides preset save/load via vendor JSON.

    Why
    - Tune sound parameters live from a reliable companion; capture/apply presets deterministically; accelerate testing.

    How
    - On launch: discover endpoints; PE GET snapshot; build UI with ranges from Facts; bind controls to PE SET with debounce (50–100 ms).
    - CC fallback (Ch.1) for quick coarse changes if PE is unavailable.
    """

    static let mrtsPrompt = """
    Scene: Quiet Frame Companion — MRTS (PE Inspector)

    Steps
    - Discover endpoints → PE GET returns properties (>= 24 properties), no error.
    - Engine Master: 0.8 → 0.5 → audible drop on Sonify; PE GET reflects 0.5.
    - Drone LPF sweep 1200→4000 Hz → Sonify brightens; frequency map within ±2%.
    - Mute toggle → silence; Panic → All Notes Off; Sonify engine remains running.
    - Preset roundtrip: save PE snapshot; modify 3 controls; load preset → PE + sound revert.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "targets": [[
                "id": "quietframe",
                "endpoint2": "Quiet Frame",
                "endpoint1": "Quiet Frame M1",
                "channel1": 1
            ]],
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
}

