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

    Proposed routes: `/probes/saliency/compare`, `/probes/align`, `/probes/ocr/recognize`, `/probes/contours`, `/probes/barcodes`.

    ## Audio Probes
    - Embedding distance: Core ML embeddings (YAMNet or custom via CoreMLKit) → cosine distance; artifacts: baseline-embed.json, candidate-embed.json.
    - Spectrogram compare: Mel/STFT via Accelerate/vDSP; metrics: L2, log‑spectral distance (dB), SSIM‑over‑mel; artifacts: baseline-spec.png, candidate-spec.png, delta-spec.png.
    - Onsets/tempo: onset times + tempo; metrics: tempo drift, onset F1 vs reference.
    - Pitch/intonation: f0 contour → cents error vs MIDI; artifacts: f0.csv, overlay.png.
    - Loudness/dynamics: RMS/peak envelopes; dynamic range; artifacts: envelope.json/png.
    - Alignment (MIDI↔audio): cross‑correlate vs click/expected note times; report latency/drift; artifact: alignment.json, aligned.wav.
    - (Optional) ASR: SFSpeechRecognizer to validate transcript snippets.

    Proposed routes: `/probes/audio/embedding/compare`, `/probes/audio/spectrogram/compare`, `/probes/audio/onsets`, `/probes/audio/pitch`, `/probes/audio/loudness`, `/probes/audio/alignment`, `/probes/audio/transcribe`.

    ## Core ML Integration (Audio)
    - Library: CoreMLKit handles load/compile/predict for `.mlmodel`/`.mlmodelc` (see `Packages/FountainApps/Sources/CoreMLKit/*`).
    - Models:
      - YAMNet (embedding/classification): fetch via `coreml-fetch yam-net --out-dir Public/Models` then convert `YAMNet.tflite` → `YAMNet.mlmodel` with `Scripts/apps/coreml-convert.sh`.
      - CREPE (pitch) / BasicPitch (poly): convert with the same script (notes in `coreml-fetch notes`).
    - Server config:
      - Env: `PBVRT_AUDIO_EMBED_MODEL` → path to `.mlmodel` (or compiled `.mlmodelc`).
      - Backend selection per request: `/probes/audio/embedding/compare` `backend: yamnet|coreml`.
      - Compute units: default `.all`; override via CoreMLKit when loading.
    - Implementation sketch:
      1) Load model (CoreMLKit.loadModel).
      2) Build input arrays from WAV (mono/stereo) with `VisionAudioHelpers.audioSamplesToMultiArray`.
      3) Run predict, extract embedding vector; compute cosine; return `AudioEmbeddingResult`.

    ## Core ML Integration (Vision — optional)
    - Current default: Apple Vision FeaturePrint for image embeddings.
    - Optional: add a CLIP‑vision Core ML encoder and compute prompt→image or image→image similarity via VNCoreMLRequest.

    ## Tests & Fixtures
    - Keep fixtures tiny: short WAVs and small PNGs for perf and deterministic CI.
    - Unit: identical‑file self‑consistency (distance ≈ 0), predictable synthetic shifts (time‑stretch, pitch shift, blur).
    - Integration: end‑to‑end probe routes write artifacts and summaries; verify presence and numeric thresholds.
    - Storage: artifacts under `.fountain/artifacts/pb-vrt/<id>/audio|vision/*`; summaries as `pbvrt.audio.*` / `pbvrt.vision.*` segments.

    ## Persistence
    - Corpus page: `pbvrt:baseline:<id>` → `pbvrt.baseline` (JSON) with artifact URIs.
    - Vision probe summaries: `pbvrt.vision.*` segments; Audio probe summaries: `pbvrt.audio.*` segments.
    - Files: `.fountain/artifacts/pb-vrt/<id>/*`.

    ## Integration
    - `/compare` composes metrics: saliency‑weighted + post‑align drift, OCR invariants, audio spectral/embedding distances.
    - Tooling: all routes carry `x-fountain.allow-as-tool: true` and can be registered into ToolsFactory.

    ## Phases & Acceptance
    - Phase 1: Vision align + OCR; Audio embed + spectrogram.
    - Phase 2: Onsets/tempo, pitch/intonation; barcode decoding.
    - Phase 3: Loudness, alignment; optional ASR and CLIP vision.
    - Pass criteria: thresholds documented next to routes; CI attaches artifacts on failure.

    """
}
