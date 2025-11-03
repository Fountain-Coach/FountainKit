import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PBVRTRigSeed {
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

        // Ensure corpus
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "patchbay", "kind": "teatro-prompts"]) } catch { }

        // Page and segments
        let appId = env["APP_ID"] ?? "pbvrt-rig"
        let pageId = "prompt:\(appId)"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://\(pageId)", host: "store", title: "PB‑VRT Test Rig — Vision & Audio")
        _ = try? await store.addPage(page)

        // Write prompt text
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro.prompt", pageId: pageId, kind: "teatro.prompt", text: promptText))

        // Facts: instruments, PE fields, invariants and thresholds
        let facts: [String: Any] = [
            "app_id": "pbvrt-rig",
            "instruments": [
                [
                    "id": "frame",
                    "name": "Frame",
                    "pe": ["canvas.zoom", "canvas.translation.x", "canvas.translation.y"],
                    "ops": ["canvas.reset", "canvas.fit", "overlay.toggle:aligned", "overlay.toggle:saliency", "overlay.toggle:delta"]
                ],
                [
                    "id": "aligner",
                    "name": "Aligner",
                    "pe": ["transform.dx", "transform.dy", "transform.scale", "transform.rotationDeg", "postAlignDriftPx", "confidence"]
                ],
                [
                    "id": "saliency",
                    "name": "Saliency Scope",
                    "pe": ["weighted_ssim", "weighted_l1"]
                ],
                [
                    "id": "reader",
                    "name": "Reader",
                    "pe": ["ocr.lineCount", "ocr.wrapColumnMedian"]
                ],
                [
                    "id": "grid",
                    "name": "Grid",
                    "pe": ["contours.spacingMeanPx", "contours.spacingStdPx", "contours.count"]
                ],
                [
                    "id": "codes",
                    "name": "Code Finder",
                    "pe": ["barcodes.payloads[]", "barcodes.types[]"]
                ],
                [
                    "id": "audio",
                    "name": "Audio Bench",
                    "pe": [
                        "audio.lsd_db", "audio.embedding_cosine",
                        "audio.tempoBpm", "audio.onsetsSec[]",
                        "audio.offsetMs", "audio.driftMs",
                        "audio.meanDb", "audio.maxDb",
                        "audio.f0Hz[]", "audio.centsErrorMean"
                    ]
                ],
                [
                    "id": "monitor",
                    "name": "Monitor",
                    "pe": ["monitor.opacity.now", "monitor.opacity.min", "monitor.fadeSeconds", "monitor.maxLines"]
                ]
            ],
            "viewports": [
                ["width": 1440, "height": 900, "scale": 1],
                ["width": 1280, "height": 800, "scale": 1]
            ],
            "invariants": [
                ["id": "pan.follow_finger", "rule": "docDelta == viewDelta/zoom", "tolerancePx": 0.5],
                ["id": "zoom.anchor_stable", "rule": "center drift <= 1 px at 1440×900", "tolerancePx": 1.0],
                ["id": "align.drift_max", "rule": "postAlignDriftPx <= 5 px", "threshold": 5.0],
                ["id": "saliency.wssim_min", "rule": "weighted_ssim >= 0.96", "threshold": 0.96],
                ["id": "pixel.l1_max", "rule": "pixel_l1 <= 0.012", "threshold": 0.012],
                ["id": "featureprint.max", "rule": "featureprint_distance <= 0.035", "threshold": 0.035],
                ["id": "audio.lsd_max", "rule": "lsd_db <= 0.5", "threshold": 0.5]
            ],
            "routes": [
                "/compare",
                "/probes/align",
                "/probes/saliency/compare",
                "/probes/ocr/recognize",
                "/probes/contours",
                "/probes/barcodes",
                "/probes/audio/spectrogram/compare",
                "/probes/audio/embedding/compare",
                "/probes/audio/onsets",
                "/probes/audio/pitch",
                "/probes/audio/loudness",
                "/probes/audio/alignment"
            ]
        ]
        if let factsData = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: factsData, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: s))
        }

        print("Seeded PB‑VRT Test Rig prompt → corpus=\(corpusId) page=\(pageId)")
    }

    static let promptText = """
    PB‑VRT Test Rig — Vision & Audio

    This surface is a quiet lab for measuring what matters. One canvas holds a golden frame and the latest render. You can nudge the view, fit it to the page, and toggle overlays that reveal how the image breathes: attention, contour lines, and pixel‑by‑pixel differences once aligned. Beside it, a small audio bench listens to two short clips and shows their spectrograms with a clear sense of pitch, pulse, and loudness. A single pass verdict appears only after both sight and sound agree with the baseline.

    The rig offers simple instruments with precise names. The Frame responds to zoom and pan and always stays true to the math: when you pan by a finger’s width, the document moves by that distance scaled by the current zoom; when you zoom, the center holds steady within a pixel at typical sizes. The Aligner learns how far the new image is shifted, scaled, or rotated, then banks that transform and shows drift after correction. The Saliency Scope dims the unimportant and weighs differences where a human would actually look. The Reader picks up text with sober accuracy and reports how the column wraps. The Grid looks for staves and spacing and tells you their average distance and spread without fanfare. The Code Finder reads a barcode or QR when it’s there and stays quiet when it isn’t.

    The Audio Bench is equally plain. It can twin two tones and report their distance in a way that feels musical, or compare two clips by their spectrograms and tell you how far they’ve drifted in timbre. It hears onsets well enough to tap the tempo, estimates pitch for a simple line, and traces a loudness curve that shows the shape of a phrase. When a baseline is present, every instrument writes its short summary and tucks artifacts into a neat folder for later inspection.

    The lab is meant to be calm, repeatable, and honest. It is not a gallery. You bring a prompt, capture a golden frame, and let the rig keep you from drifting. That is all.
    """

}
