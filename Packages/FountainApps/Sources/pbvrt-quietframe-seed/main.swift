import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PBVRTQuietFrameSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "pb-vrt-project"
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

        // Ensure corpus
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "pb-vrt", "kind": "project"]) } catch { }

        let pageId = "prompt:pbvrt-quietframe"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://\(pageId)", host: "store", title: "PB‑VRT — Quiet Frame (Golden Baseline)")
        _ = try? await store.addPage(page)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):doc", pageId: pageId, kind: "text/markdown", text: docMD))

        print("Seeded Quiet Frame prompt → corpus=\(corpusId) page=\(pageId)")
    }

    // Human‑readable prompt (content up to "Next steps")
    static let docMD = """
    # PB‑VRT — Quiet Frame (Golden Baseline)

    Unique ability — why PB‑VRT exists:
    Turn intention into auditable proof. PB‑VRT binds human intent (prompt/semantics) to precise pixel and audio geometry in a reproducible Quiet Frame, then produces proofs of change you can keep, compare, and share (baseline, drift, clip).

    ## The Golden Quiet Frame
    - Page: A4 canonical size (595×842 doc‑units at 1×; the renderer scales).
    - Margins (mm → doc‑units): top/left/bottom/right = 18/18/18/18 by default.
    - Inner content rect: reserved “semantic‑browser slot” (entire inner page by default).
    - Optional baseline grid for print rhythm: baseline.mm = 12 (hidden in golden capture).

    Behavior invariants:
    - Anchor‑stable zoom (≤ 1 px drift at typical sizes).
    - Follow‑finger pan (docDelta = viewDelta/zoom; correct sign).
    - Grid discipline (minor step × majorEvery × zoom → pixel spacing).
    - Capture discipline (same viewport/scale yields identical baseline bytes).

    Proof policy:
    - Golden proof = empty A4 page (faint border optional).
    - The semantic‑browser slot is defined but empty (baseline = silence).

    ## Minimal Instrument Set (PatchBay)
    - StageA4 (page & layout)
      - PE: stage.page, stage.margins.top/left/bottom/right, stage.baseline.mm
      - Ops: stage.fit, stage.reset
    - BrowserPane (semantic content slot)
      - PE: browser.url, browser.route, browser.padding, browser.scroll.y
      - Ops: browser.load, browser.reload
    - FrameCamera (capture discipline)
      - PE: camera.viewport.width/height/scale, camera.frameId
      - Ops: camera.capture (→ baseline.png / candidate.png), camera.lockViewport
    - DriftLens (alignment & delta)
      - PE: drift.search.windowPx, drift.postAlignDriftPx, drift.confidence
      - Ops: drift.align, drift.delta (→ aligned.png, delta.png)
    - GazeScope (saliency)
      - PE: saliency.model, saliency.weighted_ssim, saliency.weighted_l1
      - Ops: saliency.compare (→ saliency maps + weighted‑delta)
    - OCRScribe (reading & rhythm)
      - PE: ocr.language, ocr.wrapColumn, ocr.lineCount
      - Ops: ocr.recognize (→ ocr‑overlay.png, rhythm.json, caption.md)
    - VoiceprintEar (sound compare)
      - PE: audio.window, audio.hop, audio.melBands, audio.lsd_db
      - Ops: audio.spectrogram.compare (→ baseline_spec.png, candidate_spec.png, delta_spec.png)
    - Presenter (film)
      - PE: presenter.duration.s, presenter.titles.on
      - Ops: presenter.render (→ demo.mp4, poster.png)
    - Archivist (store & version)
      - PE: archivist.corpusId, archivist.baselineId
      - Ops: archivist.write (→ pbvrt.baseline, pbvrt.compare, pbvrt.vision.*, pbvrt.audio.*, teatro.clip)

    ## Minimal Flow
    1) Create baseline: StageA4.reset → FrameCamera.lockViewport → FrameCamera.capture (baseline.png) → Archivist.write pbvrt.baseline
    2) Compare candidate (geometry‑only): re‑capture → DriftLens.align + delta → GazeScope.compare → Archivist.write pbvrt.compare
    3) Extend with content (semantic‑browser slot): BrowserPane.load → capture/compare as needed; optional OCR

    ## Quiet‑Frame Invariants (seed tests)
    - Zoom anchor drift ≤ 1 px
    - Pan docDelta = viewDelta/zoom
    - Post‑align drift ≤ 5 px (geometry only baseline)
    - Saliency‑weighted SSIM ≥ 0.96 (empty‑page baseline)
    - OCR wrap column within expected range if content exists, else 0 lines

    ## Store & Artifacts
    - Segments: pbvrt.baseline, pbvrt.compare, pbvrt.vision.* (saliency/align/ocr), pbvrt.audio.* (spec/embedding)
    - Files: .fountain/artifacts/pb-vrt/<baselineId>/baseline.png, candidate.png, aligned.png, delta.png, baseline_spec.png, candidate_spec.png, delta_spec.png; optional demo.mp4, poster.png
    - A teatro.clip describing scenes (Baseline → Align/Delta → Saliency; optional Voiceprint)

    ## Why this baseline
    It gives PB‑VRT a neutral, absolute reference (empty A4) that exercises geometry and discipline without content noise. It composes cleanly with the BrowserPane in later baselines (same frame; content enters the stage; proofs remain comparable).
    """
}

