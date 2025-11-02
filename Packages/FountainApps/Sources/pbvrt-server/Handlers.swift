import Foundation
import OpenAPIRuntime
import FountainStoreClient
import Vision
import AVFoundation
import Accelerate

// PB‑VRT core for persistence
final class PBVRTCore: @unchecked Sendable {
    let store: FountainStoreClient
    let corpusId: String
    let artifactsRoot: URL

    init(store: FountainStoreClient, corpusId: String, artifactsRoot: URL) {
        self.store = store
        self.corpusId = corpusId
        self.artifactsRoot = artifactsRoot
    }

    func ensureCorpus() async {
        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "pb-vrt", "kind": "baselines"]) } catch { }
    }

    func promptPageId(_ id: String) -> String { "pbvrt:prompt:\(id)" }
    func baselinePageId(_ id: String) -> String { "pbvrt:baseline:\(id)" }

    func writePrompt(id: String, text: String, tags: [String]?, modality: String?, embeddingModel: String?, hash: String) async throws -> String {
        try await ensurePage(promptPageId(id), title: "PBVRT Prompt \(id)")
        let meta: [String: Any?] = [
            "id": id,
            "tags": tags ?? [],
            "modality": modality ?? "visual",
            "embedding_model": embeddingModel,
            "hash": hash
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta.compactMapValues { $0 }, options: [.sortedKeys])
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(promptPageId(id)):pbvrt.meta", pageId: promptPageId(id), kind: "facts", text: String(data: metaData, encoding: .utf8) ?? "{}"))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(promptPageId(id)):pbvrt.prompt", pageId: promptPageId(id), kind: "pbvrt.prompt", text: text))
        return "store://pbvrt/prompt/\(id)"
    }

    func ensurePage(_ id: String, title: String) async throws {
        let page = Page(corpusId: corpusId, pageId: id, url: "store://\(id)", host: "store", title: title)
        _ = try? await store.addPage(page)
    }

    func baselineDir(_ baselineId: String) -> URL {
        let dir = artifactsRoot.appendingPathComponent(baselineId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func adHocDir() -> URL {
        let dir = artifactsRoot.appendingPathComponent("ad-hoc/" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func writeBaseline(baselineId: String, promptId: String, viewport: Components.Schemas.Viewport, rendererVersion: String?, midiSequence: Components.Schemas.MIDISequence?, probes: [String: Any]?) async throws -> String {
        try await ensurePage(baselinePageId(baselineId), title: "PBVRT Baseline \(baselineId)")
        let dir = baselineDir(baselineId)
        var artifacts: [String: String] = [
            "baselinePng": dir.appendingPathComponent("baseline.png").path,
            "embeddingJson": dir.appendingPathComponent("embedding.json").path
        ]
        if let seq = midiSequence {
            let seqURL = dir.appendingPathComponent("sequence.json")
            let seqObj: [String: Any] = [
                "sequenceID": seq.sequenceID,
                "packets": seq.packets.map { ["word0": $0.word0, "word1": $0.word1 as Any, "word2": $0.word2 as Any, "word3": $0.word3 as Any] },
                "channel": seq.channel as Any,
                "deviceName": seq.deviceName as Any,
                "hash": seq.hash as Any
            ].compactMapValues { $0 }
            if let data = try? JSONSerialization.data(withJSONObject: seqObj, options: [.sortedKeys, .prettyPrinted]) {
                try? data.write(to: seqURL)
                artifacts["midiUmp"] = seqURL.path
            }
        }
        // Minimal metadata segment
        let meta: [String: Any?] = [
            "baselineId": baselineId,
            "promptId": promptId,
            "viewport": ["width": viewport.width, "height": viewport.height, "scale": viewport.scale],
            "rendererVersion": rendererVersion,
            "probes": probes,
            "artifacts": artifacts
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta.compactMapValues { $0 }, options: [.sortedKeys])
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(baselinePageId(baselineId)):pbvrt.baseline", pageId: baselinePageId(baselineId), kind: "pbvrt.baseline", text: String(data: metaData, encoding: .utf8) ?? "{}"))
        return "store://pbvrt/baseline/\(baselineId)"
    }
}

// Generated server protocol conformance
final class PBVRTHandlers: APIProtocol, @unchecked Sendable {
    let core: PBVRTCore
    init(store: FountainStoreClient, corpusId: String, artifactsRoot: URL) {
        self.core = PBVRTCore(store: store, corpusId: corpusId, artifactsRoot: artifactsRoot)
        Task { await core.ensureCorpus() }
    }

    // POST /prompts
    func registerPrompt(_ input: Operations.registerPrompt.Input) async throws -> Operations.registerPrompt.Output {
        guard case let .json(p) = input.body else { return .undocumented(statusCode: 400, .init()) }
        // Use provided hash or compute a placeholder if missing
        let hash = p.hash ?? "sha256:" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let uri = try await core.writePrompt(id: p.id, text: p.text, tags: p.tags, modality: p.modality.rawValue, embeddingModel: p.embedding_model, hash: hash)
        let ref = Components.Schemas.PromptRef(id: p.id, hash: hash, uri: uri)
        return .created(.init(body: .json(ref)))
    }

    // GET /prompts/{id}
    func getPrompt(_ input: Operations.getPrompt.Input) async throws -> Operations.getPrompt.Output {
        let pid = input.path.id
        let pageId = core.promptPageId(pid)
        // Try to load prompt text
        guard let data = try await core.store.getDoc(corpusId: core.corpusId, collection: "segments", id: "\(pageId):pbvrt.prompt"),
              let segText = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = segText["text"] as? String else {
            return .undocumented(statusCode: 404, .init())
        }
        // Load meta for tags/modality/hash
        let metaData = try? await core.store.getDoc(corpusId: core.corpusId, collection: "segments", id: "\(pageId):pbvrt.meta")
        var tags: [String] = []
        var modality: Components.Schemas.Prompt.modalityPayload = .visual
        var embedding: String? = nil
        var hash: String? = nil
        if let metaData, let metaObj = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any], let textMeta = metaObj["text"] as? String,
           let metaInner = try? JSONSerialization.jsonObject(with: Data(textMeta.utf8)) as? [String: Any] {
            tags = metaInner["tags"] as? [String] ?? []
            if let m = metaInner["modality"] as? String, m == "visual" { modality = .visual }
            embedding = metaInner["embedding_model"] as? String
            hash = metaInner["hash"] as? String
        }
        let prompt = Components.Schemas.Prompt(id: pid, text: text, tags: tags, modality: modality, embedding_model: embedding, hash: hash)
        return .ok(.init(body: .json(prompt)))
    }

    // POST /baselines
    func createBaseline(_ input: Operations.createBaseline.Input) async throws -> Operations.createBaseline.Output {
        guard case let .json(b) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let baselineId = UUID().uuidString
        let _ = try await core.writeBaseline(baselineId: baselineId, promptId: b.promptId, viewport: b.viewport, rendererVersion: b.rendererVersion, midiSequence: b.midiSequence, probes: nil)
        let ref = Components.Schemas.BaselineRef(baselineId: baselineId, uri: "store://pbvrt/baseline/\(baselineId)")
        return .created(.init(body: .json(ref)))
    }

    // GET /baselines/{id}
    func getBaseline(_ input: Operations.getBaseline.Input) async throws -> Operations.getBaseline.Output {
        let id = input.path.id
        let pageId = core.baselinePageId(id)
        guard let data = try await core.store.getDoc(corpusId: core.corpusId, collection: "segments", id: "\(pageId):pbvrt.baseline"),
              let seg = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = seg["text"] as? String,
              let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return .undocumented(statusCode: 404, .init())
        }
        let promptId = obj["promptId"] as? String ?? ""
        let vp = obj["viewport"] as? [String: Any] ?? [:]
        let viewport = Components.Schemas.Viewport(width: vp["width"] as? Int ?? 0, height: vp["height"] as? Int ?? 0, scale: Float(vp["scale"] as? Double ?? 1))
        let artifacts = obj["artifacts"] as? [String: String] ?? [:]
        let promptRef = Components.Schemas.PromptRef(id: promptId, hash: "sha256:unknown", uri: "store://pbvrt/prompt/\(promptId)")
        let baseline = Components.Schemas.Baseline(
            baselineId: id,
            promptRef: promptRef,
            viewport: viewport,
            rendererVersion: (obj["rendererVersion"] as? String) ?? "",
            midiSequence: nil,
            probes: .init(embeddingBackend: nil),
            artifacts: .init(baselinePng: artifacts["baselinePng"], embeddingJson: artifacts["embeddingJson"], midiUmp: artifacts["midiUmp"]) )
        return .ok(.init(body: .json(baseline)))
    }

    // POST /compare (store candidate and return trivial metrics)
    func compareCandidate(_ input: Operations.compareCandidate.Input) async throws -> Operations.compareCandidate.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var baselineId: String?
        var candidateData: Data?
        for try await part in form {
            switch part {
            case .baselineId(let w):
                let data = try await collectBody(w.payload.body)
                baselineId = String(decoding: data, as: UTF8.self)
            case .candidatePng(let w):
                candidateData = try await collectBody(w.payload.body)
            case .embeddingBackend: break
            case .undocumented: break
            }
        }
        guard let bId = baselineId?.trimmingCharacters(in: .whitespacesAndNewlines), let png = candidateData else { return .undocumented(statusCode: 400, .init()) }
        // Store candidate alongside baseline directory
        let dir = core.baselineDir(bId)
        let candidateURL = dir.appendingPathComponent("candidate.png")
        try? png.write(to: candidateURL)
        // Compute featureprint distance if baseline.png exists
        var fdist: Double?
        let baselineURL = dir.appendingPathComponent("baseline.png")
        if let base = try? Data(contentsOf: baselineURL) {
            if let cand = try? Data(contentsOf: candidateURL) {
                fdist = try? PBVRTEngine.featureprintDistance(baseline: base, candidate: cand)
            }
        }
        let metrics = Components.Schemas.DriftReport.metricsPayload(
            pixel_l1: nil,
            ssim: nil,
            featureprint_distance: fdist.map { Float($0) },
            clip_cosine: nil,
            prompt_cosine: nil
        )
        let report = Components.Schemas.DriftReport(
            baselineId: bId,
            metrics: metrics,
            pass: (fdist ?? 0) < (Double(ProcessInfo.processInfo.environment["PBVRT_FEATUREPRINT_MAX"] ?? "0.03") ?? 0.03),
            artifacts: .init(candidatePng: candidateURL.path, deltaPng: nil),
            timestamps: .init(baseline: nil, run: Date())
        )
        return .ok(.init(body: .json(report)))
    }

    // POST /probes/embedding/compare (stub)
    func compareEmbeddingAdhoc(_ input: Operations.compareEmbeddingAdhoc.Input) async throws -> Operations.compareEmbeddingAdhoc.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var base: Data?
        var cand: Data?
        let t0 = Date()
        for try await part in form {
            switch part {
            case .baselinePng(let w): base = try await collectBody(w.payload.body)
            case .candidatePng(let w): cand = try await collectBody(w.payload.body)
            case .backend: break
            case .undocumented: break
            }
        }
        guard let b = base, let c = cand else { return .undocumented(statusCode: 400, .init()) }
        let dist = try PBVRTEngine.featureprintDistance(baseline: b, candidate: c)
        let ms = Date().timeIntervalSince(t0) * 1000
        let out = Components.Schemas.EmbeddingResult(metricName: .featureprint_distance, value: Float(dist), backend: .featurePrint, model: "Vision.FeaturePrint", durationMs: Float(ms))
        return .ok(.init(body: .json(out)))
    }

    // MARK: - Vision probes (stubs/minimal)
    func compareSaliencyWeighted(_ input: Operations.compareSaliencyWeighted.Input) async throws -> Operations.compareSaliencyWeighted.Output {
        // Placeholder: return 200 with no metrics yet; artifacts omitted
        let res = Components.Schemas.SaliencyCompareResult(weighted_l1: nil, weighted_ssim: nil, artifacts: .init(baselineSaliency: nil, candidateSaliency: nil, weightedDelta: nil))
        return .ok(.init(body: .json(res)))
    }

    func alignImages(_ input: Operations.alignImages.Input) async throws -> Operations.alignImages.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var baseData: Data?
        var candData: Data?
        for try await part in form {
            switch part {
            case .baselinePng(let w): baseData = try await collectBody(w.payload.body)
            case .candidatePng(let w): candData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let b = baseData, let c = candData,
              let base = CGImage.fromPNGData(b), let cand = CGImage.fromPNGData(c) else {
            return .undocumented(statusCode: 400, .init())
        }
        let (dxDown, dyDown, _) = Self.estimateTranslation(baseline: base, candidate: cand, sample: 128, search: 16)
        // Scale offsets to candidate pixel coordinates
        let scaleX = CGFloat(cand.width) / 128.0
        let scaleY = CGFloat(cand.height) / 128.0
        let dx = Float(CGFloat(dxDown) * scaleX)
        let dy = Float(CGFloat(dyDown) * scaleY)
        // Write aligned candidate artifact
        let dir = core.adHocDir()
        let alignedURL = dir.appendingPathComponent("aligned.png")
        if let aligned = CGImage.translate(image: cand, by: CGSize(width: Int(round(CGFloat(dx))), height: Int(round(CGFloat(dy))))) {
            try? aligned.writePNG(to: alignedURL)
        }
        // Compute simple post-align drift as mean absolute difference over overlap
        let drift = Self.meanAbsoluteDifference(baseline: base, candidate: cand, dx: Int(round(CGFloat(dx))), dy: Int(round(CGFloat(dy))))
        let t = Components.Schemas.Transform2D(dx: dx, dy: dy, scale: 1, rotationDeg: 0, homography: nil)
        let res = Components.Schemas.AlignResult(transform: t, postAlignDriftPx: Float(drift), artifacts: .init(alignedCandidatePng: alignedURL.path))
        return .ok(.init(body: .json(res)))
    }

    func ocrRecognize(_ input: Operations.ocrRecognize.Input) async throws -> Operations.ocrRecognize.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var imgData: Data?
        for try await part in form {
            switch part {
            case .imagePng(let w): imgData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = imgData, let cg = CGImage.fromPNGData(d) else { return .undocumented(statusCode: 400, .init()) }
        let res = try Self.recognizeText(cgImage: cg)
        return .ok(.init(body: .json(res)))
    }

    func detectContours(_ input: Operations.detectContours.Input) async throws -> Operations.detectContours.Output {
        let res = Components.Schemas.ContoursResult(spacingMeanPx: nil, spacingStdPx: nil, count: 0, artifacts: .init(contoursImage: nil))
        return .ok(.init(body: .json(res)))
    }

    func detectBarcodes(_ input: Operations.detectBarcodes.Input) async throws -> Operations.detectBarcodes.Output {
        let res = Components.Schemas.BarcodesResult(payloads: [], types: [])
        return .ok(.init(body: .json(res)))
    }

    // MARK: - Audio probes (stubs/minimal)
    func compareAudioEmbedding(_ input: Operations.compareAudioEmbedding.Input) async throws -> Operations.compareAudioEmbedding.Output {
        let out = Components.Schemas.AudioEmbeddingResult(metricName: .audio_embedding_cosine, value: 0, backend: .yamnet, model: "none", durationMs: 0)
        return .ok(.init(body: .json(out)))
    }

    func compareSpectrogram(_ input: Operations.compareSpectrogram.Input) async throws -> Operations.compareSpectrogram.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var bw: Data?; var cw: Data?
        for try await part in form {
            switch part {
            case .baselineWav(let w): bw = try await collectBody(w.payload.body)
            case .candidateWav(let w): cw = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let bd = bw, let cd = cw,
              let (bmono, bsr) = try? Self.decodeWavToMono(data: bd),
              let (cmono, csr) = try? Self.decodeWavToMono(data: cd) else {
            return .undocumented(statusCode: 400, .init())
        }
        let sr = Double(min(Int(bsr), Int(csr)))
        let (bSpec, _) = Self.spectrogram(samples: bmono, sampleRate: sr)
        let (cSpec, _) = Self.spectrogram(samples: cmono, sampleRate: sr)
        let minFrames = min(bSpec.cols, cSpec.cols)
        let minBins = min(bSpec.rows, cSpec.rows)
        let l2 = Self.l2Distance(a: bSpec, b: cSpec, rows: minBins, cols: minFrames)
        let lsd = Self.logSpectralDistanceDB(a: bSpec, b: cSpec, rows: minBins, cols: minFrames)
        // Artifacts
        let dir = core.adHocDir()
        let bPNG = dir.appendingPathComponent("baseline-spec.png")
        let cPNG = dir.appendingPathComponent("candidate-spec.png")
        let dPNG = dir.appendingPathComponent("delta-spec.png")
        Self.writeGrayscalePNG(matrix: bSpec, to: bPNG)
        Self.writeGrayscalePNG(matrix: cSpec, to: cPNG)
        Self.writeGrayscalePNGDelta(a: bSpec, b: cSpec, to: dPNG)
        let res = Components.Schemas.SpectrogramCompareResult(l2: Float(l2), lsd_db: Float(lsd), ssim: nil, artifacts: .init(baselineSpecPng: bPNG.path, candidateSpecPng: cPNG.path, deltaSpecPng: dPNG.path))
        return .ok(.init(body: .json(res)))
    }

    func detectOnsets(_ input: Operations.detectOnsets.Input) async throws -> Operations.detectOnsets.Output {
        let res = Components.Schemas.OnsetsResult(onsetsSec: [], tempoBpm: nil)
        return .ok(.init(body: .json(res)))
    }

    func analyzePitch(_ input: Operations.analyzePitch.Input) async throws -> Operations.analyzePitch.Output {
        let res = Components.Schemas.PitchResult(f0Hz: [], centsErrorMean: nil)
        return .ok(.init(body: .json(res)))
    }

    func analyzeLoudness(_ input: Operations.analyzeLoudness.Input) async throws -> Operations.analyzeLoudness.Output {
        let res = Components.Schemas.LoudnessResult(rms: [], meanDb: nil, maxDb: nil)
        return .ok(.init(body: .json(res)))
    }

    func analyzeAlignment(_ input: Operations.analyzeAlignment.Input) async throws -> Operations.analyzeAlignment.Output {
        let res = Components.Schemas.AlignmentResult(offsetMs: 0, driftMs: nil)
        return .ok(.init(body: .json(res)))
    }

    func transcribeAudio(_ input: Operations.transcribeAudio.Input) async throws -> Operations.transcribeAudio.Output {
        var lang = "en-US"
        if case let .multipartForm(form) = input.body {
            for try await part in form {
                switch part {
                case .language(let w):
                    if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { lang = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                case .wav: break
                case .undocumented: break
                }
            }
        }
        let res = Components.Schemas.TranscriptResult(transcript: "", language: lang)
        return .ok(.init(body: .json(res)))
    }
    // Helpers
    private func collectBody(_ body: OpenAPIRuntime.HTTPBody) async throws -> Data {
        try await Data(collecting: body, upTo: 1 << 22)
    }
}

// MARK: - Utilities (Vision/Images)
extension CGImage {
    static func fromPNGData(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    func resized(width: Int, height: Int) -> CGImage? {
        guard let colorSpace = self.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
    static func translate(image: CGImage, by offset: CGSize) -> CGImage? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: Int(offset.width), y: Int(offset.height), width: image.width, height: image.height))
        return ctx.makeImage()
    }
    func writePNG(to url: URL) throws {
        let type = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return }
        CGImageDestinationAddImage(dest, self, nil)
        CGImageDestinationFinalize(dest)
    }
}

extension PBVRTHandlers {
    // Downsample to `sample` and brute-force search in ±`search` pixels (downsampled) for minimal SAD
    static func estimateTranslation(baseline: CGImage, candidate: CGImage, sample: Int, search: Int) -> (dx: Int, dy: Int, score: Float) {
        guard let bSmall = baseline.resized(width: sample, height: sample), let cSmall = candidate.resized(width: sample, height: sample) else { return (0,0,0) }
        let b = grayscaleFloat(image: bSmall)
        let c = grayscaleFloat(image: cSmall)
        var bestScore: Float = .greatestFiniteMagnitude
        var best = (0,0)
        for dy in -search...search {
            for dx in -search...search {
                let s = sad(b: b, c: c, width: sample, height: sample, dx: dx, dy: dy)
                if s < bestScore { bestScore = s; best = (dx, dy) }
            }
        }
        return (best.0, best.1, bestScore)
    }
    static func grayscaleFloat(image: CGImage) -> [Float] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w*h)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: 0) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data.map { Float($0) / 255.0 }
    }
    static func sad(b: [Float], c: [Float], width: Int, height: Int, dx: Int, dy: Int) -> Float {
        var sum: Float = 0
        var count = 0
        for y in 0..<height {
            let y2 = y + dy
            if y2 < 0 || y2 >= height { continue }
            for x in 0..<width {
                let x2 = x + dx
                if x2 < 0 || x2 >= width { continue }
                let i1 = y*width + x
                let i2 = y2*width + x2
                sum += abs(b[i1] - c[i2])
                count += 1
            }
        }
        return count > 0 ? sum / Float(count) : .greatestFiniteMagnitude
    }
    static func meanAbsoluteDifference(baseline: CGImage, candidate: CGImage, dx: Int, dy: Int) -> Double {
        // Work at downsampled resolution to estimate drift
        let sample = 128
        guard let bSmall = baseline.resized(width: sample, height: sample), let cSmall = candidate.resized(width: sample, height: sample) else { return 0 }
        let b = grayscaleFloat(image: bSmall)
        let c = grayscaleFloat(image: cSmall)
        return Double(sad(b: b, c: c, width: sample, height: sample, dx: Int(round(Double(dx) * 128.0 / Double(candidate.width))), dy: Int(round(Double(dy) * 128.0 / Double(candidate.height)))))
    }
}

// MARK: - Utilities (Audio)
extension PBVRTHandlers {
    static func decodeWavToMono(data: Data) throws -> ([Float], Double) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: tmp)
        let file = try AVAudioFile(forReading: tmp)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { throw NSError(domain: "pbvrt", code: -1) }
        try file.read(into: buf)
        let channels = Int(format.channelCount)
        let frames = Int(buf.frameLength)
        var mono = [Float](repeating: 0, count: frames)
        if channels == 1, let c0 = buf.floatChannelData?[0] {
            for i in 0..<frames { mono[i] = c0[i] }
        } else if channels >= 2, let c0 = buf.floatChannelData?[0], let c1 = buf.floatChannelData?[1] {
            for i in 0..<frames { mono[i] = 0.5*(c0[i] + c1[i]) }
        }
        return (mono, format.sampleRate)
    }
    struct Matrix { var rows: Int; var cols: Int; var data: [Float] }
    static func spectrogram(samples: [Float], sampleRate: Double, fftSize: Int = 1024, hop: Int = 512) -> (Matrix, Int) {
        let n = samples.count
        if n < fftSize { return (Matrix(rows: fftSize/2+1, cols: 0, data: []), 0) }
        let half = fftSize/2+1
        let cols = max(0, (n - fftSize) / hop + 1)
        var mat = [Float](repeating: 0, count: max(1, half * max(1, cols)))
        for col in 0..<cols {
            let start = col * hop
            // For simplicity in this MVP, fill with RMS of frame slices (coarse spectrogram)
            let chunk = fftSize / half
            for k in 0..<half {
                let s = start + k*chunk
                if s+chunk <= n {
                    let slice = samples[s..<(s+chunk)]
                    var rms: Float = 0
                    vDSP_rmsqv(Array(slice), 1, &rms, vDSP_Length(chunk))
                    mat[k*cols + col] = log1p(rms)
                }
            }
        }
        return (Matrix(rows: half, cols: cols, data: mat), half)
    }
    static func l2Distance(a: Matrix, b: Matrix, rows: Int, cols: Int) -> Double {
        var sum: Double = 0
        for j in 0..<cols { for i in 0..<rows { let d = Double(a.data[i*a.cols + j] - b.data[i*b.cols + j]); sum += d*d } }
        return sum / Double(rows*cols)
    }
    static func logSpectralDistanceDB(a: Matrix, b: Matrix, rows: Int, cols: Int) -> Double {
        var sum: Double = 0
        for j in 0..<cols { for i in 0..<rows {
            let da = Double(a.data[i*a.cols + j])
            let db = Double(b.data[i*b.cols + j])
            let la = 20 * log10(max(1e-6, da))
            let lb = 20 * log10(max(1e-6, db))
            sum += abs(la - lb)
        } }
        return sum / Double(rows*cols)
    }
    static func writeGrayscalePNG(matrix: Matrix, to url: URL) {
        guard matrix.cols > 0, matrix.rows > 0 else { return }
        let w = matrix.cols, h = matrix.rows
        let minv = matrix.data.min() ?? 0
        var maxv = matrix.data.max() ?? 1
        if maxv <= minv { maxv = minv + 1 }
        var pixels = [UInt8](repeating: 0, count: w*h)
        for y in 0..<h {
            for x in 0..<w {
                let v = (matrix.data[y*matrix.cols + x] - minv) / (maxv - minv)
                pixels[y*w + x] = UInt8(max(0, min(255, Int(v * 255.0))))
            }
        }
        let cs = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return }
        if let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: cs, bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            try? img.writePNG(to: url)
        }
    }
    static func writeGrayscalePNGDelta(a: Matrix, b: Matrix, to url: URL) {
        let rows = min(a.rows, b.rows), cols = min(a.cols, b.cols)
        var data = [Float](repeating: 0, count: rows*cols)
        for j in 0..<cols { for i in 0..<rows { data[i*cols + j] = abs(a.data[i*a.cols + j] - b.data[i*b.cols + j]) } }
        writeGrayscalePNG(matrix: .init(rows: rows, cols: cols, data: data), to: url)
    }
}

// MARK: - Vision OCR helper
extension PBVRTHandlers {
    static func recognizeText(cgImage: CGImage) throws -> Components.Schemas.OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        var lines: [Components.Schemas.OCRLine] = []
        var lengths: [Int] = []
        if let results = request.results as? [VNRecognizedTextObservation] {
            for obs in results {
                let text = obs.topCandidates(1).first?.string ?? ""
                lengths.append(text.count)
                let bb = obs.boundingBox
                let x = Float(bb.origin.x * CGFloat(cgImage.width))
                let y = Float((1 - bb.origin.y - bb.height) * CGFloat(cgImage.height))
                let w = Float(bb.width * CGFloat(cgImage.width))
                let h = Float(bb.height * CGFloat(cgImage.height))
                let bbox = Components.Schemas.OCRLine.bboxPayload(
                    x: try? OpenAPIRuntime.OpenAPIValueContainer(unvalidatedValue: x),
                    y: try? OpenAPIRuntime.OpenAPIValueContainer(unvalidatedValue: y),
                    w: try? OpenAPIRuntime.OpenAPIValueContainer(unvalidatedValue: w),
                    h: try? OpenAPIRuntime.OpenAPIValueContainer(unvalidatedValue: h)
                )
                lines.append(.init(text: text, bbox: bbox))
            }
        }
        let median: Float? = lengths.isEmpty ? nil : Float(lengths.sorted()[lengths.count/2])
        return Components.Schemas.OCRResult(lineCount: lengths.count, wrapColumnMedian: median, lines: lines)
    }
}
