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
        // Minimal stub: return empty metrics; can be expanded to run VNSaliency
        let res = Components.Schemas.SaliencyCompareResult(
            weighted_l1: nil,
            weighted_ssim: nil,
            artifacts: .init(baselineSaliency: nil, candidateSaliency: nil, weightedDelta: nil)
        )
        return .ok(.init(body: .json(res)))
    }

    func alignImages(_ input: Operations.alignImages.Input) async throws -> Operations.alignImages.Output {
        // Minimal stub: identity transform; post-align drift 0
        let t = Components.Schemas.Transform2D(dx: 0, dy: 0, scale: 1, rotationDeg: 0, homography: nil)
        let res = Components.Schemas.AlignResult(transform: t, postAlignDriftPx: 0, artifacts: .init(alignedCandidatePng: nil))
        return .ok(.init(body: .json(res)))
    }

    func ocrRecognize(_ input: Operations.ocrRecognize.Input) async throws -> Operations.ocrRecognize.Output {
        // Minimal OCR summary without running Vision OCR
        let res = Components.Schemas.OCRResult(lineCount: 0, wrapColumnMedian: nil, lines: [])
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
        let res = Components.Schemas.SpectrogramCompareResult(l2: 0, lsd_db: nil, ssim: nil, artifacts: .init(baselineSpecPng: nil, candidateSpecPng: nil, deltaSpecPng: nil))
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
