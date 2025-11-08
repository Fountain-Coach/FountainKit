import Foundation
import FountainStoreClient
import Crypto

@main
struct DieMaschineTeatroSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "die-maschine"
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")

        let client: FountainStoreClient
        do { client = FountainStoreClient(client: try DiskFountainStoreClient(rootDirectory: root)) }
        catch { print("seed: failed to init store: \(error)"); return }

        // Ensure corpus exists
        do { _ = try await client.createCorpus(corpusId, metadata: ["app": "die-maschine", "kind": "teatro"]) } catch { }

        // Page: main Teatro prompt
        let pageId = "prompt:die-maschine"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://prompt/die-maschine", host: "store", title: "Die Maschine träumt — Teatro"))

        // Human-readable Teatro prompt
        let teatro = """
        Die Maschine träumt — Teatro (Acts, Scenes, Samplers)

        What
        - Each Akt owns one midi2sampler instance in a neutral "default" state (program TBD). Acts are containers for Scenes; Scenes carry the current instrumentation and reference one or more Scores (Notensetzungen / Engravings). Scenes may host a nested "Rehearsals" container for work‑in‑progress instrumental mappings.

        Why
        - Keep the creative structure legible while the instrument state remains interchangeable. The sampler default is intentionally undefined; provenance and determinism are carried by Store facts and Engravings.

        How (profile)
        - Transport: MIDI 2.0 first; BLE/RTP via midi2. No CoreMIDI.
        - Engine: midi2sampler per Akt (one instance), default program; PE channels gated by facts.
        - Scenes: two or more per Akt; order is flexible. Scenes attach Scores (Engravings) for later realization. The optional "rehearsals" list lives inside a Scene and holds instrumentation variants (e.g., draft channel maps for midi2sampler).

        Notes
        - The in-app routing panel is removed. Orchestration remains Store-backed (Partiture YAML; routing blueprint) for reference and tools.
        - This prompt is the source of truth; edits happen here and in facts.
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: teatro))

        // Facts (machine-readable)
        let acts: [[String: Any]] = (1...5).map { i in
            let actId = "act\(i)"
            let sampler: [String: Any] = [
                "engine": "midi2sampler",
                "instanceId": "sampler-\(actId)",
                "program": "default",
                "group": 0,
                "notes": "undefined"
            ]
            let scenes: [[String: Any]] = [
                [
                    "id": "\(actId)-scene-1",
                    "title": "Scene 1",
                    "order": 1,
                    "instrumentation": "placeholder",
                    "engravings": [] as [String],
                    "rehearsals": [] as [[String: Any]]
                ],
                [
                    "id": "\(actId)-scene-2",
                    "title": "Scene 2",
                    "order": 2,
                    "instrumentation": "placeholder",
                    "engravings": [] as [String],
                    "rehearsals": [] as [[String: Any]]
                ]
            ]
            return [
                "id": actId,
                "title": "Akt \(i)",
                "sampler": sampler,
                "scenes": scenes
            ]
        }

        let facts: [String: Any] = [
            "prompt.version": 1,
            "policy": ["coremidi": 0, "midi2": 1, "ble": 1, "rtp": 1],
            "defaults": ["sampler.program": "default"],
            "acts": acts,
            "glossary": [
                "Scene": "Unit inside an Akt; carries instrumentation and references scores (Engravings).",
                "Engraving": "Notensatz; a specific scoring/engraving referenced by a Scene."
            ]
        ]

        var teatroETag = ""
        var factsETag = ""
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: text))
            factsETag = sha256Hex(text)
        }
        teatroETag = sha256Hex(teatro)

        // Index page with links + ETags
        let indexPage = "docs:die-maschine:index"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: indexPage, url: "store://docs/die-maschine/index", host: "store", title: "Index — Die Maschine"))
        let indexDoc = """
        Die Maschine — Index

        Links
        - Teatro: prompt:die-maschine:teatro (etag=\(teatroETag))
        - Facts:  prompt:die-maschine:facts  (etag=\(factsETag))
        - Partiture (stub): docs:die-maschine:partiture:doc
        - CC Mapping (stub): docs:die-maschine:cc-mapping:doc
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(indexPage):doc", pageId: indexPage, kind: "doc", text: indexDoc))

        // Stub pages for Partiture and CC mapping (reserved anchors)
        let partiturePage = "docs:die-maschine:partiture"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: partiturePage, url: "store://docs/die-maschine/partiture", host: "store", title: "Partiture — Die Maschine (stub)"))
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(partiturePage):doc", pageId: partiturePage, kind: "doc", text: "(stub)"))

        let ccPage = "docs:die-maschine:cc-mapping"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: ccPage, url: "store://docs/die-maschine/cc-mapping", host: "store", title: "CC Mapping — Die Maschine (stub)"))
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(ccPage):doc", pageId: ccPage, kind: "doc", text: "{\n  \"cc\": []\n}"))

        // Doc: Sampler Profile (programBase + overrides semantics)
        let samplerDocPage = "docs:die-maschine:sampler-profile"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: samplerDocPage, url: "store://docs/die-maschine/sampler-profile", host: "store", title: "Sampler Profile — midi2sampler"))
        let samplerDoc = """
        Sampler Profile — midi2sampler (Die Maschine)

        What
        - Each Akt owns a midi2sampler instance. Scenes may carry an instrumentation mapping that is based on a base program and refined by mapping overrides.

        Semantics
        - programBase: "default" (intentional placeholder) — curated later.
        - mapping.channels: ordered channel list with names (e.g., 1: vl1, 2: vl2…). Channels map to sampler parts/slots.
        - overrides (future): per-channel program, gain, ADSR, filter, layer blending — optional and Scene‑scoped.
        - PE: publish bank/program/params via vendor JSON first, then full MIDI‑CI Property Exchange. GET/SET apply to the active Akt sampler.

        Transport
        - MIDI 2.0 UMP first; BLE/RTP per venue. No CoreMIDI. Downgrade to MIDI‑1 is explicit and avoided here.
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(samplerDocPage):doc", pageId: samplerDocPage, kind: "doc", text: samplerDoc))

        // Doc: UI Plan (Acts & Scenes browser)
        let uiPlanPage = "docs:die-maschine:ui-plan"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: uiPlanPage, url: "store://docs/die-maschine/ui-plan", host: "store", title: "UI Plan — Acts & Scenes Browser"))
        let uiPlan = """
        UI Plan — Acts & Scenes Browser (Read‑Only v1)

        Views
        - Sidebar: Acts (I–V)
        - Main list: Scenes of selected Act (order asc)
        - Detail: Scene header + Instrumentation mapping table (channels → names); sampler profile summary.

        Behavior
        - Read facts from prompt:die-maschine:facts; no edits in v1.
        - Show ETag (facts) to ensure provenance.
        - Later: enable Scene reordering and per‑channel overrides (always Store‑backed).
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(uiPlanPage):doc", pageId: uiPlanPage, kind: "doc", text: uiPlan))

        print("Seeded Die Maschine Teatro → corpus=\(corpusId) page=\(pageId) acts=5 etag.teatro=\(teatroETag.prefix(12))… etag.facts=\(factsETag.prefix(12))…")
    }
}

// MARK: - Helpers
func sha256Hex(_ s: String) -> String {
    let digest = SHA256.hash(data: Data(s.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
