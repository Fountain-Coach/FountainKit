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
        await seedDramaturgy(store, corpusId: corpusId)
        await seedActII(store, corpusId: corpusId)
        // Seed integrated MIDI Bridge prompt (instrument within the app)
        await seedBridge(store, corpusId: corpusId)
        await seedUIBlueprint(store, corpusId: corpusId)
        await seedRouting(store, corpusId: corpusId)
        print("Seeded QuietFrame Sonify prompts + dramaturgy + bridge → corpus=\(corpusId) pages=[\(pageId), \(mrtId), prompt:quietframe-bridge, docs:quietframe:act1, reviews:quietframe:act2:cell-collider]")
    }

    static let creationPrompt = """
    Scene: QuietFrame Instrument — Act I “Saliency” (ML polyphonic sonification)
    
    What
    - A single-window macOS instrument renders a radial saliency field and sonifies presence.
    - The audio engine (SDLKit) is augmented by an ML analysis pipeline that evaluates stereo output and emits a polyphonic MIDI 2.0 note stream; these notes are re‑sonified to make recognition audible.
    - The instrument exposes a formal MIDI 2.0 CI/PE surface (authoritative). An OpenAPI Params mirror may be used for development and tests. GUI follows Engraver baseline: a top toolbar (ScoreKit/RulesKit metrics) with Act/Section/BPM and essential controls. No floating overlay HUD.
    
    Why
    - Act I dramaturgy: “QuietFrame Note — On Saliency and Presence” and “Die Maschine träumt von Xenakis”. Attention becomes resonance. ML transcription externalizes what the machine “heard” as notes; sonification returns that awareness to the listener. PB‑VRT frames anchor repeatability.
    
    How (engine, mapping, gestures)
    - Engine: zero‑alloc SDLKit callback; layers = drone, clock, breath, overtones, FX (plate ≤12%, delay ≤30% fb), limiter.
    - Mapping (default):
        • frequencyHz = 220 + saliency.now × 660
        • amplitude = min(0.25, saliency.now × 0.20)
        • drone.lpfHz = 300 + saliency.now × 2200
        • breath.centerHz = 1200 + saliency.now × 3200
        • overtones.mix = smoothstep(0.35, 0.85, saliency.now)
        • x → timbre tilt (brighter to the right); y → density/space (more ghosts + reverb)
        • Threshold gate (default 0.65): emits short harmonic ping; hysteresis 0.03.
    - ML analysis: hop 20–46 ms, window 1024–2048, latency target ≤50 ms; produces onsets/offsets/velocities; optional tag stream.
    - Polyphonic re‑sonify: voice manager (poly cap), ADSR (A/R), velocity→amp, PB support; per‑note updates in callback.
    - MIDI 2.0 policy: CI discovery required; PE Get/Set + Notify for all state changes. Channel Voice 2.0 reserved for performance (Note On/Off from analysis, Pitch Bend). OpenAPI Params mirror is a dev convenience and must remain CI‑equivalent.
    - Journaling (PB‑VRT): log tNs, saliency snapshot, UMP batches (CC/Note), PE bundles (Set/Notify), engine snapshot. Quiet Frame invariants: mapping (±2%), envelope timing (±5%), latency ≤50 ms, sustained chord RMS stability.

    Bluetooth MIDI (HUD)
    - HUD shows a Bluetooth icon. Tap brings up a panel with two roles, mirroring AUM:
      • Central — Find & connect with devices. Shows a live list (name, RSSI) with connect/disconnect; optional target filter. Facts: ble.mode=central, ble.scan, ble.devices[], ble.connected, ble.targetName, rx/tx counters. Ops: ble.scan.start/stop, ble.connect(nameSubstr), ble.disconnect.
      • Peripheral — Advertise this device. Controls for Advertise on/off and advertised name (default "QuietFrame#<instanceId>"). Facts: ble.mode=peripheral, ble.advertising, ble.advertised.name, ble.connectedPeers. Ops: ble.advertise.start(name), ble.advertise.stop.
    - Transport policy: CoreMIDI is prohibited. BLE and RTP MIDI 2.0 run via our midi2 stack; Loopback used for sidecar/tests. SysEx7 (MIDI‑CI/PE) is fully supported and chunked appropriately for BLE MTU.
    
    Where
    - Code: MetalViewKit (instrument/renderer), FountainAudioEngine (engine), analysis/* (ML pipeline).
    - Protocol: CI/PE via MetalInstrument; UMP Note stream (Loopback/System). OpenAPI mirror (Sidecar) for observability/testing.
    - Corpus: FountainStore corpus ‘quietframe‑sonify’; Act I dramaturgy stored under docs:quietframe:act1; Act II “Cell Collider” reviews tracker prepared.
    """

    static let mrtsPrompt = """
    Scene: QuietFrame Sonify — MRTS (SDLKit × Act I × Midified × Sidecar)
    
    Steps
    1) audio.test.ping → audible 200 ms ping; returns { ok:true, rms≥0.05 }.
    2) Params GET initial state (OpenAPI): zoom=1, translation=0, saliency.now≈0 (cursor outside), audio.engine='sdlkit'.
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

    BLE HUD
    - Default mode: off. On tapping Bluetooth icon, switching to Central shows device list within 3–10 seconds; manual scan toggle available.
    - Switching to Peripheral starts advertising with name "QuietFrame#<instanceId>" and reports ble.advertising=true.
    - No CoreMIDI surfaces are present.
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
                    "rec.start",
                    "rec.stop",
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
            "openapi": [
                "baseURL": "http://127.0.0.1:7777",
                "params": [
                    "GET /v1/params",
                    "GET /v1/params/{id}",
                    "PATCH /v1/params",
                    "GET /v1/params/stream"],
                "presets": [
                    "GET /v1/presets",
                    "POST /v1/presets",
                    "POST /v1/presets/{name}/apply"],
                "bridge": ["OpenAPI ⇄ MIDI‑CI Property Exchange"]
            ],
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
                "ciRequired": true,
                "peNamespace": "quietframe",
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
                "midi2": ["endpoints": ["Quiet Frame"], "ump": ["group":0]],
                "note": ["threshold": 0.65, "scale":"pentatonic", "base":60, "hysteresis":0.03]
            ],
            "synth": [
                "enabled": true,
                "waveform": "saw",
                "polyphonyLimit": 16,
                "attackMs": 5,
                "releaseMs": 180
            ],
            "analysis": [
                "enabled": true,
                "modelId": "polyphonic-ml",
                "hopMs": 23,
                "window": 1024,
                "latencyGoalMs": 50
            ]
            ,
            "ble": [
                "hud": true,
                "defaultMode": "off",
                "modes": ["central","peripheral"],
                "ops": [
                    "ble.mode.set",
                    "ble.scan.start","ble.scan.stop","ble.connect","ble.disconnect",
                    "ble.advertise.start","ble.advertise.stop"
                ],
                "facts": [
                    "ble.mode","ble.scan","ble.target.name","ble.devices","ble.connected",
                    "ble.advertising","ble.advertised.name","ble.connectedPeers",
                    "ble.rx.count","ble.tx.count","ble.rssi"
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }

    // MARK: - Additional seeding: dramaturgical references and Act II reviews stub
    static func seedDramaturgy(_ store: FountainStoreClient, corpusId: String) async {
        let fs = FileManager.default
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dieMaschine = repoRoot.appendingPathComponent("Public/Die_Maschine_traeumt_von_Xenakis_FINAL.md")
        let quietNote = repoRoot.appendingPathComponent("Public/QuietFrame_Note.md")
        let pageId = "docs:quietframe:act1"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://docs/quietframe/act1", host: "store", title: "QuietFrame — Dramaturgy (Act I)"))
        if let data = try? Data(contentsOf: dieMaschine), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):die-maschine-traeumt", pageId: pageId, kind: "doc", text: text))
        } else {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):die-maschine-traeumt:ref", pageId: pageId, kind: "ref", text: "Public/Die_Maschine_traeumt_von_Xenakis_FINAL.md"))
        }
        if let data = try? Data(contentsOf: quietNote), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):quietframe-note", pageId: pageId, kind: "doc", text: text))
        } else {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):quietframe-note:ref", pageId: pageId, kind: "ref", text: "Public/QuietFrame_Note.md"))
        }
        // Reviews tracker for Act II (Hook: Cell Collider)
        let reviewsId = "reviews:quietframe:act2:cell-collider"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: reviewsId, url: "store://reviews/quietframe/act2/cell-collider", host: "store", title: "Reviews — Act II: Cell Collider"))
        let seedReviewIndex = "# Reviews — Act II: Cell Collider\n\nAdd entries as JSON lines or Markdown bullets; journaled with tNs and tags."
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(reviewsId):index", pageId: reviewsId, kind: "doc", text: seedReviewIndex))
    }

    // MARK: - Act II (Cell Collider) — prompts & facts (prompt-first)
    static func seedActII(_ store: FountainStoreClient, corpusId: String) async {
        let page = "prompt:quietframe-act2"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: page, url: "store://prompt/quietframe/act2", host: "store", title: "QuietFrame — Act II (Cell Collider)"))
        let creation = """
        Scene: QuietFrame Instrument — Act II “Cell Collider” (Cells talk via MIDI‑CI/PE)

        What
        - QuietFrame becomes a cell‑automata instrument (2D lattice). A rule (Life by default) evolves the grid; activations/collisions emit MIDI 2.0 notes.
        - CI/PE is authoritative (Get/Set/Notify) for the grid, rules, seed, and clock. CV2 UMP is used for performance only (Note On/Off, optional PB). Journaling yields deterministic replay.

        Why
        - Act I was presence→resonance. Act II is interaction→exchange: autonomous cells collide and “talk” using CI/PE (state) and CV2 (performance). No musical quantization.

        How
        - Grid: width×height, wrap (toroidal) or bounded. Rules: life|seeds|highlife|custom(mask).
        - Clock: step.hz drives evolution; run.state (running|paused); step.once advances one generation.
        - MIDI policy: CI/PE for state; CV2 for performance on events; Notify mirrors state after each Set.
        - Journaling: per tick: tNs, PE bundle, UMP batch, stateHash, density.

        Invariants
        - Deterministic evolution given seed+rule+step.hz; PE Get round‑trips; Notify after each Set; note cap per tick; tNs monotonic.
        """
        let mrts = """
        MR Test Plan — Act II (Cell Collider)
        - PE Get/Set: cells.grid.*, cells.rule.*, cells.seed.*, cells.step.hz, cells.run.state, cells.step.once
        - Determinism: seed+rule+N ticks → stateHash matches fixtures
        - Emissions: note count per tick ≤ cap; velocity correlates with local neighbor count; optional PB within ±50 cents
        - Evidence: Journal contains PE+UMP per tick; replay reproduces batches
        """
        let facts: [String: Any] = [
            "app": "quietframe-act2",
            "midi": ["ciRequired": true, "peNamespace": "cells", "cv2": ["group": 0, "channel": 0]],
            "ui": ["prompt.version": 2, "layout": "engraver.toolbar.top"],
            "acts.map": [
                ["code": 1, "short": "I",   "label": "Genesis des Rauschens"],
                ["code": 2, "short": "II",  "label": "Topologie des Schalls"],
                ["code": 3, "short": "III", "label": "Formalismus träumt"],
                ["code": 4, "short": "IV",  "label": "Die Stimme der Architektur"],
                ["code": 5, "short": "V",   "label": "Das Schweigen"]
            ],
            "cells": [
                "grid": ["width": 64, "height": 40, "wrap": true],
                "rule": ["name": "life"],
                "seed": ["kind": "random"],
                "stepHz": 8,
                "emit": ["mode": "collisions", "rateCap": 128]
            ],
            "journal": ["enabled": true, "include": ["pe","ump","stateHash"]]
        ]
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):teatro", pageId: page, kind: "teatro.prompt", text: creation))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):mrts", pageId: page, kind: "teatro.prompt", text: mrts))
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):facts", pageId: page, kind: "facts", text: text))
        }
    }

    // MARK: - UI Blueprint (doc)
    static func seedUIBlueprint(_ store: FountainStoreClient, corpusId: String) async {
        let page = "docs:quietframe:ui-blueprint"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: page, url: "store://docs/quietframe/ui-blueprint", host: "store", title: "UI Blueprint — Engraver Toolbar"))
        let doc = """
        UI Blueprint — QuietFrame (Engraver Toolbar, v2)

        Layout
        - Top toolbar, Engraver baseline (ScoreKit spacing, RulesKit alignment).
        - Items: Akt picker (I–V) → title label (acts.map) | Divider | Satz (section) stepper | Divider | BPM slider + readout | Divider | Mute/Panic/Test icons.
        - BLE indicator remains on the right (Central, TX/RX blink + counters).

        Routing Overlay (v3)
        - Central overlay instrument for routing: Sources | Destinations | Routes | Monitor.
        - Actions: connect/disconnect; future: learn CC/channel, remap, mirror UMP↔︎MIDI 1.0.
        - North star: AUM’s MIDI 1.0 surface clarity; we preserve UMP semantics internally.

        Tokens (EngraverTokens)
        - Spacing: xs=4, s=6, m=10, l=14, xl=20
        - Metrics: toolbarControlWidth=120, toolbarCornerRadius=6

        Facts
        - ui.prompt.version=3
        - ui.layout=engraver.toolbar.top+routing.overlay.center
        - acts.map: [ {code, short, label} ] — see prompt:quietframe-act2:facts
        """
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):doc", pageId: page, kind: "doc", text: doc))
    }

    // MARK: - Routing (AUM‑inspired matrix, v4)
    static func seedRouting(_ store: FountainStoreClient, corpusId: String) async {
        let page = "prompt:quietframe-routing"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: page, url: "store://prompt/quietframe/routing", host: "store", title: "QuietFrame — MIDI Routing Matrix (AUM‑inspired, Central)"))
        let teatro = """
        What
        - AUM‑style square matrix: rows = sources, columns = destinations, cells = routes. Shows at fixed aspect (1:1), centered, summoned by “Routing…” (⌘R). Non‑blocking; canvas stays interactive when closed.
        - Internal truth is UMP; per‑route we optionally down‑map to MIDI‑1 (channel mask) and filter message classes (CV2/M1/PE/Utility).

        Why
        - Fast topology edits with a glanceable grid that scales (dozens of endpoints). Matches AUM operator muscle memory; preserves MIDI 2.0 semantics.

        Visual Traits (AUM‑inspired)
        - Square matrix; 1 px crisp grid lines; diagonal hatch for invalid cells.
        - Row labels: left band, icons (BLE/RTP/local) + status dot; horizontal text.
        - Column labels: top band, rotated 90°, icons + type badge.
        - Cell states: off (outline), on (filled + inner highlight + tiny right‑arrow glyph), hover/focus (keyline ring + tooltip), filtered (tiny badges CV2/M1/PE), invalid (hatch, disabled cursor).
        - Micro‑animations: toggle flicker (30–60 ms), Inspector scale+fade (120 ms), arrow draw (25 ms).

        Behavior
        - Click toggles route. Option‑click/right‑click opens Inspector.
        - Shift‑drag sweeps cells to toggle in bulk.
        - Keyboard: arrows move focus; Space toggles; Enter opens Inspector; Esc closes panel.
        - Panel opened by toolbar/menu; remembers size/position.

        Inspector (per cell)
        - channelMask (1–16, All), group (0–15), filters {cv2, m1, pe, utility}.
        - Caption: <source> → <destination>. Apply/Remove route.

        Persistence
        - Save/Load routes as a routing blueprint doc; no CoreMIDI, BLE/RTP only via midi2 transport.
        """
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):teatro", pageId: page, kind: "teatro.prompt", text: teatro))
        let facts: [String: Any] = [
            "ui": ["prompt.version": 4, "layout": "engraver.toolbar.top+routing.panel.matrix.square"],
            "matrix": ["square": true, "gridPx": 1, "rowLabelIcons": true, "colTopRotated": true, "hatchInvalid": true],
            "defaults": [
                "group": 0,
                "channelMask": "all",
                "filters": ["cv2": 1, "m1": 1, "pe": 1, "utility": 1]
            ],
            "tokens": [
                "spacing": ["xs": 4, "s": 6, "m": 10, "l": 14, "xl": 20],
                "colors": ["grid": "#FFFFFF22", "tileOn": "#3A82FF", "tileHover": "#FFFFFF12", "hatch": "#FFFFFF10"]
            ],
            "iconMap": ["ble": "wave.3", "rtp": "dot.radiowaves.left.and.right", "local": "square.stack.3d.down.right"],
            "sources": [], "destinations": [], "routes": []
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):facts", pageId: page, kind: "facts", text: text))
        }
        let blueprint = """
        Routing Blueprint (v4)
        - routes: Array of { row:Int, col:Int, channelMask:[Int]|"all", group:Int, filters:{cv2:0/1,m1:0/1,pe:0/1,utility:0/1} }
        - sources/destinations are discovered at runtime (BLE central, RTP, local instrument).
        """
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):blueprint", pageId: page, kind: "doc", text: blueprint))
    }
    // MARK: - BLE MIDI (Central‑only)
    static func seedBridge(_ store: FountainStoreClient, corpusId: String) async {
        let page = "prompt:quietframe-bridge"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: page, url: "store://prompt/quietframe-bridge", host: "store", title: "QuietFrame — MIDI Bridge (Integrated)"))
        let teatro = """
        Scene: QuietFrame — BLE‑MIDI (Central only)

        What
        - QuietFrame acts as a BLE‑MIDI Central and auto‑connects to a BLE‑MIDI Peripheral (e.g., AUM on iPad). No CoreMIDI anywhere.
        - UMP is the internal format; the BLE path maps UMP↔︎MIDI 1.0 as needed.

        Why
        - Deterministic, crash‑free transport on Swift 6. Simpler UX: always Central.

        How
        - Auto‑scan on launch; connect to the first match (or an optional filter substring).
        - Discrete HUD hint (indicator dot) blinks when sending.

        CI/PE (subset)
        - `ble.target.name` (string; optional filter)
        - `ble.status.connected` (0/1, ro); `ble.status.device` (string, ro); `ble.status.rssi` (int, ro if available)
        - `ble.tx.count` (int, ro), `ble.lastSendNs` (string, ro)

        Evidence
        - Journal remains UMP‑first. BLE adds ≤10 ms p95 under typical loads.
        """
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):teatro", pageId: page, kind: "teatro.prompt", text: teatro))
        let facts: [String: Any] = [
            "ble": [
                "target.name": "",
                "status": ["connected": 0, "device": "", "rssi": 0],
                "tx": ["count": 0, "lastSendNs": "0"]
            ],
            "midi": ["format": "ump", "cv2": ["group": 0, "channel": 0]],
            "ui": ["prompt.version": 3, "layout": "engraver.toolbar.top+routing.overlay.center"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(page):facts", pageId: page, kind: "facts", text: text))
        }
    }
}
