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
    Scene: QuietFrame Sonify — Saliency Testing + Csound
    What
    - A single‑window macOS app that presents one “Quiet Frame” (1024×1536 pt) centered on a neutral background.
    - Moving the cursor over the Quiet Frame computes a scalar saliency and sonifies it via Csound. Small HUD shows saliency and CC1 value.
    - MIDI 2.0 identity: “QuietFrame#<instance>”; Property Exchange exposes cursor and saliency properties.
    Why
    - Minimal, deterministic surface for saliency + audio feedback without graph editors.
    How
    - Saliency (center radial): 1.0 at center → 0.0 at corners.
    - MIDI: CC1=round(saliency*127). On crossing threshold (0.65), emit a pentatonic note around middle C, velocity from saliency.
    - Csound: RtMidi CoreMIDI input, listens on Ch.1 for CC1 + Note.
    Where
    - App executable: quietframe-sonify-app; seed target: quietframe-sonify-seed.
    """

    static let mrtsPrompt = """
    Scene: QuietFrame Sonify — MRTS
    Steps
    1) PE GET initial state: zoom=1, translation=0, saliency=0.
    2) Move to corners: saliency ≤ 0.02, CC1≈0.
    3) Move to center: saliency ≥ 0.98, CC1≈127.
    4) Sweep diagonal: saliency monotonic increasing within ±0.02 tolerance.
    5) Threshold=0.60: trigger note on crossing; release when below with hysteresis 0.03.
    6) Random walk: mean 0.35..0.65; coverage ≥ 0.5 of range.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "instruments": [
                ["id": "quietframe", "product": "QuietFrame", "ports": [["id": "out", "dir": "out", "kind": "saliency"]], "pe": ["zoom","translation.x","translation.y","cursor.view.x","cursor.view.y","cursor.doc.x","cursor.doc.y","cursor.inside","saliency.now","saliency.mode","saliency.threshold","scan.enabled","scan.speed","scan.path"]]
            ],
            "midi": ["cc1": "saliency.now"],
            "note": ["threshold": 0.65, "scale": "pentatonic", "base": 60]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}

