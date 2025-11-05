import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct QuietFrameSonifySeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "quietframe-sonify"
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

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "quietframe-sonify", "kind": "teatro"]) } catch { }

        let pageId = "prompt:quietframe-sonify"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://prompt/quietframe-sonify", host: "store", title: "QuietFrame Sonify — Creation"))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))
        if let facts = factsJSON() { _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts)) }
        let mrtId = "prompt:quietframe-sonify-mrts"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: mrtId, url: "store://prompt/quietframe-sonify-mrts", host: "store", title: "QuietFrame Sonify — MRTS"))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtId):teatro", pageId: mrtId, kind: "teatro.prompt", text: mrtsPrompt))
        print("Seeded QuietFrame Sonify prompts → corpus=\(corpusId) pages=[\(pageId), \(mrtId)]")
    }

    static let creationPrompt = """
    Scene: QuietFrame Sonify — Act I “Awakening” with SDLKit Audio (Midified)
    
    What
    - A single-window macOS app (“Quiet Frame”: 1024×1536 pt) computing saliency and rendering a coherent soundscape via an embedded SDLKit engine (autarkic).
    - The synth engine mirrors Act I (Die Maschine träumt): drone bed, clock pulses, breath/noise texture, and emergent harmonic overtones.
    - All engine parameters are midified: controllable via MIDI 2.0 Property Exchange (PE) and optionally via MIDI 1.0 CC (Ch.1) for companion tuning.
    - HUD: saliency, Mute, Panic (All Notes Off), Test (200 ms ping), and Act controls (Section, BPM, Key/Scale).
    
    Why
    - Deterministic saliency testing with reliable audio and tunable parameters, aligned to a musical narrative of an awakening machine.
    
    How (engine, mapping, gestures)
    - Engine: SDLKit callback (float32, stereo @ 48 kHz; ~256 block size). No allocations in callback; thread-safe parameter updates.
      Layers:
        • Drone: dual saw (polyBLEP) + sine sub; LPF 12/24 dB; gentle saturation.
        • Clock: percussive sine ticks paced by tempo; probabilistic ghost notes.
        • Breath: pink/white noise → BP/HP blend; envelope; breathiness from saliency & y.
        • Overtones: FM/additive partials in key/scale; chorus shimmer; note gates on threshold.
        • FX: plate (≤12% wet), tape delay (1/8|1/4, feedback ≤0.3), soft limiter.
    - Mapping (default):
        • frequencyHz = 220 + saliency.now × 660
        • amplitude = min(0.25, saliency.now × 0.20)
        • drone.lpfHz = 300 + saliency.now × 2200
        • breath.centerHz = 1200 + saliency.now × 3200
        • overtones.mix = smoothstep(0.35, 0.85, saliency.now)
        • x → timbre tilt (brighter to the right); y → density/space (more ghosts + reverb)
        • Threshold gate (default 0.65): emits short harmonic ping; hysteresis 0.03.
    - MIDI control (Companion):
        • PE is the source of truth (GET/SET/snapshot); vendor JSON for test ping/section/harmony.
        • MIDI 1.0 CC fallback on Ch.1 for coarse control (see Facts: cc map).
    
    Where
    - App: quietframe-sonify-app (engine = SDLKit by default); seed: quietframe-sonify-seed.
    - Optional external path: Csound (binds to “QuietFrame M1”), not required for audio.
    """

    static let mrtsPrompt = """
    Scene: QuietFrame Sonify — MRTS (SDLKit × Act I × Midified)
    
    Steps
    1) audio.test.ping → audible 200 ms ping; returns { ok:true, rms≥0.05 }.
    2) PE GET initial state: zoom=1, translation=0, saliency.now≈0 (cursor outside), audio.engine='sdlkit'.
    3) Move to corners: saliency.now ≤ 0.02, engine amplitude → near 0.
    4) Move to center: saliency.now ≥ 0.98, frequency≈880 Hz; amplitude≈0.20..0.25.
    5) Sweep diagonal: saliency monotonic within ±0.02; frequency mapping within ±2%.
    6) Threshold=0.60: cross → harmonic ping; drop below threshold−0.03 → release.
    7) Mute → silence; Panic → All Notes Off; engine keeps running.
    
    Invariants
    - frequencyHz = 220 + s×660 ± 2%.
    - amplitude = min(0.25, s×0.20) ± 0.02.
    - audio.test.ping: ok=true; rms≥0.05.
    - threshold gate hysteresis = 0.03.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "instruments": [[
                "id": "quietframe",
                "product": "QuietFrame",
                "ports": [["id": "out", "dir": "out", "kind": "saliency"]],
                "pe": [
                    "zoom","translation.x","translation.y",
                    "cursor.view.x","cursor.view.y",
                    "cursor.doc.x","cursor.doc.y",
                    "cursor.inside",
                    "saliency.now","saliency.mode","saliency.threshold",
                    "audio.engine","audio.sampleRate","audio.blockSize","audio.muted",
                    "act.section","tempo.bpm","harmony.key","harmony.scale",
                    "engine.masterGain",
                    "drone.amp","drone.lpfHz","drone.reso","drone.detune","drone.mixSaw",
                    "clock.level","clock.div","clock.ghostProbability",
                    "breath.level","breath.centerHz","breath.width",
                    "overtones.mix","overtones.modIndex","overtones.chorus",
                    "fx.plate.mix","fx.delay.mix","fx.delay.feedback","fx.limiter.threshold"
                ],
                "vendorJSON": [
                    "ui.cursor.set",
                    "saliency.computeAt",
                    "audio.set",
                    "audio.test.ping",
                    "act.set",
                    "tempo.set",
                    "harmony.set",
                    "preset.save",
                    "preset.load"
                ]
            ]],
            "audio": [
                "defaultEngine": "sdlkit",
                "sampleRate": 48000,
                "blockSize": 256,
                "channels": 2,
                "format": "float32",
                "mapping": [
                    "frequencyHz = 220 + saliency.now * 660",
                    "amplitude = min(0.25, saliency.now * 0.20)",
                    "drone.lpfHz = 300 + saliency.now * 2200",
                    "breath.centerHz = 1200 + saliency.now * 3200",
                    "overtones.mix = smoothstep(0.35, 0.85, saliency.now)"
                ],
                "test": ["durationMs":200, "freqHz":660, "amp":0.25, "minRMS":0.05]
            ],
            "act": [
                "name": "Awakening",
                "sections": [[
                    "id":"A0","title":"Init","layers":["drone"]
                ],[
                    "id":"A1","title":"Clockwork","layers":["drone","clock"]
                ],[
                    "id":"A2","title":"Breath","layers":["drone","clock","breath"]
                ],[
                    "id":"A3","title":"Emergence","layers":["drone","clock","breath","overtones"]
                ]]
            ],
            "midi": [
                "enabled": true,
                "midi1": [
                    "virtualSource": "QuietFrame M1",
                    "channel": 1,
                    "cc": [
                        "7":"engine.masterGain",
                        "74":"drone.lpfHz",
                        "79":"drone.reso",
                        "71":"drone.mixSaw",
                        "73":"drone.detune",
                        "20":"clock.level",
                        "21":"clock.div",
                        "22":"clock.ghostProbability",
                        "23":"breath.level",
                        "24":"breath.centerHz",
                        "25":"breath.width",
                        "26":"overtones.mix",
                        "27":"overtones.modIndex",
                        "28":"overtones.chorus",
                        "29":"fx.plate.mix",
                        "30":"fx.delay.mix",
                        "31":"fx.delay.feedback"
                    ]
                ],
                "midi2": ["endpoints": ["Quiet Frame"]],
                "note": ["threshold": 0.65, "scale":"pentatonic", "base":60, "hysteresis":0.03]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}
