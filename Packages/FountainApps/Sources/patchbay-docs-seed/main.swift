import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PatchbayDocsSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "patchbay"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url: URL
                if dir.hasPrefix("~") {
                    url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
                } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "patchbay", "kind": "docs"]) } catch { }

        let pageId = "docs:pb-vrt-vision-audio"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://docs/pb-vrt-vision-audio", host: "store", title: "PB‑VRT — Vision + Audio Probes (Spec & Plan)")
        _ = try? await store.addPage(page)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):doc", pageId: pageId, kind: "text/markdown", text: docMD))

        // facts summary for quick linking
        let facts: [String: Any] = [
            "kind": "pb-vrt-docs",
            "store": ["corpus": corpusId, "page": pageId, "segment": "doc"],
            "vision_endpoints": ["/probes/saliency", "/probes/align", "/probes/ocr/recognize", "/probes/contours", "/probes/barcodes"],
            "audio_endpoints": ["/probes/audio/embedding/compare", "/probes/audio/spectrogram/compare", "/probes/audio/onsets", "/probes/audio/pitch", "/probes/audio/loudness", "/probes/audio/alignment"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: s))
        }
        print("Seeded PB‑VRT Vision+Audio doc → corpus=\(corpusId) page=\(pageId)")
    }

    static let docMD = """
    # PB‑VRT — Vision + Audio Probes (Spec & Plan)

    Purpose: extend Prompt‑Bound Visual Regression Testing beyond pixel/SSIM into Vision‑aware image probes and Audio probes for AudioTalk and MIDI‑driven flows. All probes persist metrics and artifacts under `.fountain/artifacts/pb-vrt/<baselineId>/` and store summaries in FountainStore.

    ## Vision Probes
    - Saliency‑weighted drift: VNGenerateAttention/Objectness saliency; weighted pixel/L1/SSIM; artifacts: saliency.png, weighted-delta.png.
    - Registration‑aware drift: VNTranslational/VNHomographic registration → {dx,dy,scale,rotation,homography}; post‑align anchor drift; artifacts: aligned.png, transform.json.
    - OCR invariants: VNRecognizeTextRequest (accurate) → wrap.column, lineCount, text snippets; margin checks via boxes; artifacts: ocr.json, ocr-overlay.png.
    - Page/margins/horizon: VNDetectRectanglesRequest + VNDetectHorizonRequest to validate A4 L/R/T/B and roll.
    - Contours/grid spacing: VNDetectContoursRequest; spacing mean/std; artifacts: contours.svg/png.
    - Tracking (temporal): VNTrackObjectRequest across frames to measure jitter.
    - Barcodes: VNDetectBarcodesRequest; decode run IDs.

    Proposed routes: `/probes/saliency`, `/probes/align`, `/probes/ocr/recognize`, `/probes/contours`, `/probes/barcodes`.

    ## Audio Probes
    - Embedding distance: Core ML/YAMNet embeddings via SoundAnalysis or VNCoreMLRequest; cosine distance; artifacts: baseline-embed.json, candidate-embed.json.
    - Spectrogram compare: Mel/STFT via Accelerate/vDSP; metrics: L2, log‑spectral distance (dB), SSIM‑over‑mel; artifacts: baseline-spec.png, candidate-spec.png, delta-spec.png.
    - Onsets/tempo: onset times + tempo; metrics: tempo drift, onset F1 vs reference.
    - Pitch/intonation: f0 contour → cents error vs MIDI; artifacts: f0.csv, overlay.png.
    - Loudness/dynamics: RMS/peak envelopes; dynamic range; artifacts: envelope.json/png.
    - Alignment (MIDI↔audio): cross‑correlate vs click/expected note times; report latency/drift; artifact: alignment.json, aligned.wav.
    - (Optional) ASR: SFSpeechRecognizer to validate transcript snippets.

    Proposed routes: `/probes/audio/embedding/compare`, `/probes/audio/spectrogram/compare`, `/probes/audio/onsets`, `/probes/audio/pitch`, `/probes/audio/loudness`, `/probes/audio/alignment`, `/probes/audio/transcribe`.

    ## Persistence
    - Corpus page: `pbvrt:baseline:<id>` → `pbvrt.baseline` (JSON) with artifact URIs.
    - Vision probe summaries: `pbvrt.vision.*` segments; Audio probe summaries: `pbvrt.audio.*` segments.
    - Files: `.fountain/artifacts/pb-vrt/<id>/*`.

    ## Integration
    - /compare composes metrics: saliency‑weighted + post‑align drift, OCR invariants, audio spectral/embedding distances.
    - Tooling: all routes carry `x-fountain.allow-as-tool: true` and can be registered into ToolsFactory.

    ## Next Steps
    - Extend `v1/pb-vrt.yml` with the listed routes; implement in `pbvrt-server` and add focused tests with fixtures.

    """
}

