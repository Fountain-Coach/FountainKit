import Foundation
import OpenAPIRuntime
import FountainStoreClient
import Vision
import AVFoundation
import CoreMLKit
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

    @discardableResult
    func writeBaselineSummary(baselineId: String, kind: String, payload: [String: Any]) async -> String {
        let pageId = baselinePageId(baselineId)
        await ensureCorpus()
        do {
            try await ensurePage(pageId, title: "PBVRT Baseline \(baselineId)")
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
                _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):\(kind)", pageId: pageId, kind: kind, text: s))
            }
        } catch {
            // best-effort
        }
        return pageId
    }

    /// Writes an ad-hoc summary segment into FountainStore for visibility when no baselineId is present.
    /// Returns the page id used for the write.
    @discardableResult
    func writeAdHocSummary(kind: String, payload: [String: Any]) async -> String {
        let pageId = "pbvrt:adhoc:" + UUID().uuidString
        do {
            try await ensurePage(pageId, title: "PBVRT AdHoc — \(kind)")
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
                _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):\(kind)", pageId: pageId, kind: kind, text: s))
            }
        } catch {
            // best-effort only
        }
        return pageId
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

    // POST /baselines/{id}/capture — upload PNG and compute optional embedding
    func captureBaseline(_ input: Operations.captureBaseline.Input) async throws -> Operations.captureBaseline.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let bId = input.path.id
        var pngData: Data?; var backend: String = "featurePrint"
        for try await part in form {
            switch part {
            case .baselinePng(let w): pngData = try await collectBody(w.payload.body)
            case .embeddingBackend(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { backend = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .undocumented: break
            }
        }
        guard let png = pngData else { return .undocumented(statusCode: 400, .init()) }
        let dir = core.baselineDir(bId)
        let baselineURL = dir.appendingPathComponent("baseline.png")
        try? png.write(to: baselineURL)
        // Prepare embedding JSON placeholder (vector computation may be added later)
        let embeddingModel = (backend == "featurePrint") ? "Vision.FeaturePrint" : "coreML"
        let embeddingVec: [Float] = []
        let embURL = dir.appendingPathComponent("embedding.json")
        let embObj: [String: Any] = [
            "model": embeddingModel,
            "vector": embeddingVec
        ]
        if let d = try? JSONSerialization.data(withJSONObject: embObj, options: [.sortedKeys]) { try? d.write(to: embURL) }
        // Update baseline page with artifacts reference if not present
        _ = await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.baseline", payload: [
            "promptId": "",
            "viewport": [:],
            "rendererVersion": "",
            "artifacts": [
                "baselinePng": baselineURL.path,
                "embeddingJson": embURL.path
            ]
        ])
        // Return Baseline summary
        let promptRef = Components.Schemas.PromptRef(id: "", hash: "sha256:unknown", uri: "store://pbvrt/prompt/")
        let baseline = Components.Schemas.Baseline(
            baselineId: bId,
            promptRef: promptRef,
            viewport: .init(width: 0, height: 0, scale: 1),
            rendererVersion: "",
            midiSequence: nil,
            probes: .init(embeddingBackend: nil),
            artifacts: .init(baselinePng: baselineURL.path, embeddingJson: embURL.path, midiUmp: nil)
        )
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
        // Compute metrics if baseline.png exists
        var fdist: Double?
        var pixelL1: Double?
        var ssim: Double?
        var deltaPath: String?
        var deltaFullPath: String?
        let baselineURL = dir.appendingPathComponent("baseline.png")
        if let base = try? Data(contentsOf: baselineURL) {
            if let cand = try? Data(contentsOf: candidateURL) {
                fdist = try? PBVRTEngine.featureprintDistance(baseline: base, candidate: cand)
                if let bImg = CGImage.fromPNGData(base), let cImg = CGImage.fromPNGData(cand) {
                    // Align candidate to baseline (coarse + refine) at 256²
                    let (dxDown, dyDown, _) = Self.estimateTranslation(baseline: bImg, candidate: cImg, sample: 128, search: 16)
                    let (dxRef, dyRef, _) = Self.refineTranslation(baseline: bImg, candidate: cImg, coarseDX: dxDown, coarseDY: dyDown, coarseSample: 128, refineSample: 256, window: 6)
                    // Compute pixel L1 (mean absolute difference) on full-res overlap using dx,dy scaled from 256 sample
                    let scaleX = CGFloat(cImg.width) / 256.0
                    let scaleY = CGFloat(cImg.height) / 256.0
                    let dx = Int(round(CGFloat(dxRef) * scaleX))
                    let dy = Int(round(CGFloat(dyRef) * scaleY))
                    pixelL1 = Self.meanAbsoluteDifference(baseline: bImg, candidate: cImg, dx: dx, dy: dy)
                    // SSIM on normalized 256² grayscale using uniform weights
                    let sample = 256
                    if let bRes = bImg.resized(width: sample, height: sample), let cRes = cImg.resized(width: sample, height: sample) {
                        let bGray = PBVRTHandlers.grayscaleFloat(image: bRes)
                        let cGray = PBVRTHandlers.grayscaleFloat(image: cRes)
                        // Saliency-weighted SSIM using gradient-based saliency
                        let bSal = PBVRTHandlers.saliencyMap(fromGrayscale: bGray, width: sample, height: sample)
                        let cSal = PBVRTHandlers.saliencyMap(fromGrayscale: cGray, width: sample, height: sample)
                        var w = [Float](repeating: 0, count: sample*sample)
                        for i in 0..<(sample*sample) { w[i] = 0.5 * (bSal[i] + cSal[i]) }
                        ssim = PBVRTHandlers.weightedSSIM(a: bGray, b: cGray, weight: w, count: sample*sample)
                        // Delta artifact (abs difference) at 256²
                        var delta = [Float](repeating: 0, count: sample*sample)
                        for i in 0..<(sample*sample) { delta[i] = abs(bGray[i] - cGray[i]) }
                        let dURL = dir.appendingPathComponent("delta.png")
                        PBVRTHandlers.writeGrayscalePNG(matrix: .init(rows: sample, cols: sample, data: delta), to: dURL)
                        deltaPath = dURL.path
                    }
                    // Full-res delta artifact
                    let bGrayFull = PBVRTHandlers.grayscaleFloat(image: bImg)
                    let cGrayFull = PBVRTHandlers.grayscaleFloat(image: cImg)
                    var full = [Float](repeating: 0, count: bImg.width * bImg.height)
                    for y in 0..<bImg.height {
                        for x in 0..<bImg.width {
                            let idx = y * bImg.width + x
                            full[idx] = abs(bGrayFull[idx] - cGrayFull[idx])
                        }
                    }
                    let dfURL = dir.appendingPathComponent("delta_full.png")
                    PBVRTHandlers.writeGrayscalePNG(matrix: .init(rows: bImg.height, cols: bImg.width, data: full), to: dfURL)
                    deltaFullPath = dfURL.path
                }
            }
        }
        let metrics = Components.Schemas.DriftReport.metricsPayload(
            pixel_l1: pixelL1.map { Float($0) },
            ssim: ssim.map { Float($0) },
            featureprint_distance: fdist.map { Float($0) },
            clip_cosine: nil,
            prompt_cosine: nil
        )
        let report = Components.Schemas.DriftReport(
            baselineId: bId,
            metrics: metrics,
            pass: (fdist ?? 0) < (Double(ProcessInfo.processInfo.environment["PBVRT_FEATUREPRINT_MAX"] ?? "0.03") ?? 0.03),
            artifacts: .init(candidatePng: candidateURL.path, deltaPng: deltaPath, deltaFullPng: deltaFullPath),
            timestamps: .init(baseline: nil, run: Date())
        )
        // Persist compare summary under the baseline page
        await core.ensureCorpus()
        let pageId = core.baselinePageId(bId)
        do {
            try await core.ensurePage(pageId, title: "PBVRT Baseline \(bId)")
            let payload: [String: Any] = [
                "baselineId": bId,
                "metrics": [
                    "featureprint_distance": fdist as Any,
                    "pixel_l1": pixelL1 as Any,
                    "ssim": ssim as Any
                ],
                "artifacts": [
                    "candidatePng": candidateURL.path,
                    "deltaPng": deltaPath as Any,
                    "deltaFullPng": deltaFullPath as Any
                ],
                "runAt": ISO8601DateFormatter().string(from: Date())
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
                _ = try? await core.store.addSegment(.init(corpusId: core.corpusId, segmentId: "\(pageId):pbvrt.compare", pageId: pageId, kind: "pbvrt.compare", text: s))
            }
        } catch {
            // best-effort persistence
        }
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
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var baseData: Data?; var candData: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .baselinePng(let w): baseData = try await collectBody(w.payload.body)
            case .candidatePng(let w): candData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let bd = baseData, let cd = candData,
              let bImg = CGImage.fromPNGData(bd), let cImg = CGImage.fromPNGData(cd) else {
            return .undocumented(statusCode: 400, .init())
        }
        let sample = 256
        let bRes = bImg.resized(width: sample, height: sample) ?? bImg
        let cRes = cImg.resized(width: sample, height: sample) ?? cImg
        let bGray = PBVRTHandlers.grayscaleFloat(image: bRes)
        let cGray = PBVRTHandlers.grayscaleFloat(image: cRes)
        // Use gradient-based saliency (deterministic for tests)
        let bSal = PBVRTHandlers.saliencyMap(fromGrayscale: bGray, width: sample, height: sample)
        let cSal = PBVRTHandlers.saliencyMap(fromGrayscale: cGray, width: sample, height: sample)
        // Combine saliency (average) and compute weighted L1
        var num: Double = 0, den: Double = 0
        for i in 0..<(sample*sample) {
            let s = 0.5 * Double(bSal[i] + cSal[i])
            let d = abs(Double(bGray[i]) - Double(cGray[i]))
            num += d * s
            den += s
        }
        let wL1 = den > 0 ? num / den : 0
        // Artifacts
        let dir = core.adHocDir()
        let bSalURL = dir.appendingPathComponent("baseline-saliency.png")
        let cSalURL = dir.appendingPathComponent("candidate-saliency.png")
        let wDeltaURL = dir.appendingPathComponent("weighted-delta.png")
        PBVRTHandlers.writeGrayscalePNG(matrix: .init(rows: sample, cols: sample, data: bSal), to: bSalURL)
        PBVRTHandlers.writeGrayscalePNG(matrix: .init(rows: sample, cols: sample, data: cSal), to: cSalURL)
        // Weighted delta visualization
        var wd = [Float](repeating: 0, count: sample*sample)
        var maxv: Float = 1
        for i in 0..<(sample*sample) { wd[i] = Float(abs(Double(bGray[i]) - Double(cGray[i])) * 0.5 * Double(bSal[i] + cSal[i])); maxv = max(maxv, wd[i]) }
        PBVRTHandlers.writeGrayscalePNG(matrix: .init(rows: sample, cols: sample, data: wd.map { $0 / maxv }), to: wDeltaURL)
        let wSSIM = PBVRTHandlers.weightedSSIM(a: bGray, b: cGray, weight: zip(bSal, cSal).map { 0.5 * ($0 + $1) }, count: sample*sample)
        let res = Components.Schemas.SaliencyCompareResult(weighted_l1: Float(wL1), weighted_ssim: Float(wSSIM), artifacts: .init(baselineSaliency: bSalURL.path, candidateSaliency: cSalURL.path, weightedDelta: wDeltaURL.path))
        let payload: [String: Any] = [
            "weighted_l1": wL1,
            "weighted_ssim": wSSIM,
            "artifacts": [
                "baselineSaliency": bSalURL.path,
                "candidateSaliency": cSalURL.path,
                "weightedDelta": wDeltaURL.path
            ]
        ]
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.vision.saliency", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.vision.saliency", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    func alignImages(_ input: Operations.alignImages.Input) async throws -> Operations.alignImages.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var baseData: Data?
        var candData: Data?
        var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .baselinePng(let w): baseData = try await collectBody(w.payload.body)
            case .candidatePng(let w): candData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let b = baseData, let c = candData,
              let base = CGImage.fromPNGData(b), let cand = CGImage.fromPNGData(c) else {
            return .undocumented(statusCode: 400, .init())
        }
        // Coarse estimate
        let (dxDown, dyDown, _) = Self.estimateTranslation(baseline: base, candidate: cand, sample: 128, search: 16)
        // Refine around coarse estimate at higher resolution
        let (dxRef, dyRef, bestScore) = Self.refineTranslation(baseline: base, candidate: cand, coarseDX: dxDown, coarseDY: dyDown, coarseSample: 128, refineSample: 256, window: 6)
        // Scale offsets to candidate pixel coordinates (from refine sample)
        let scaleX = CGFloat(cand.width) / 256.0
        let scaleY = CGFloat(cand.height) / 256.0
        let dx = Float(CGFloat(dxRef) * scaleX)
        let dy = Float(CGFloat(dyRef) * scaleY)
        // Write aligned candidate artifact
        let dir = core.adHocDir()
        let alignedURL = dir.appendingPathComponent("aligned.png")
        if let aligned = CGImage.translate(image: cand, by: CGSize(width: Int(round(CGFloat(dx))), height: Int(round(CGFloat(dy))))) {
            try? aligned.writePNG(to: alignedURL)
        }
        // Compute simple post-align drift as mean absolute difference over overlap
        let drift = Self.meanAbsoluteDifference(baseline: base, candidate: cand, dx: Int(round(CGFloat(dx))), dy: Int(round(CGFloat(dy))))
        // Confidence from normalized SAD at refine sample scale
        let norm = max(1.0, Double(256 * 256))
        let confidence = max(0.0, 1.0 - Double(bestScore)/norm)
        let t = Components.Schemas.Transform2D(dx: dx, dy: dy, scale: 1, rotationDeg: 0, homography: nil)
        let res = Components.Schemas.AlignResult(transform: t, postAlignDriftPx: Float(drift), confidence: Float(confidence), artifacts: .init(alignedCandidatePng: alignedURL.path))
        let payload: [String: Any] = [
            "dx": Double(dx),
            "dy": Double(dy),
            "postAlignDriftPx": drift,
            "confidence": confidence,
            "artifacts": ["alignedCandidatePng": alignedURL.path]
        ]
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.vision.align", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.vision.align", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    func ocrRecognize(_ input: Operations.ocrRecognize.Input) async throws -> Operations.ocrRecognize.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var imgData: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .imagePng(let w): imgData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = imgData, let cg = CGImage.fromPNGData(d) else { return .undocumented(statusCode: 400, .init()) }
        let res = try Self.recognizeText(cgImage: cg)
        let payload: [String: Any] = [
            "lineCount": res.lineCount as Any,
            "wrapColumnMedian": res.wrapColumnMedian as Any
        ].compactMapValues { $0 }
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.vision.ocr", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.vision.ocr", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    func detectContours(_ input: Operations.detectContours.Input) async throws -> Operations.detectContours.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var imgData: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .imagePng(let w): imgData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = imgData, let cg = CGImage.fromPNGData(d) else { return .undocumented(statusCode: 400, .init()) }
        let (stats, overlayURL) = try PBVRTHandlers.contoursStatsAndOverlay(cgImage: cg)
        let res = Components.Schemas.ContoursResult(spacingMeanPx: Float(stats.mean), spacingStdPx: Float(stats.std), count: stats.count, artifacts: .init(contoursImage: overlayURL?.path))
        let payload: [String: Any] = [
            "spacingMeanPx": stats.mean,
            "spacingStdPx": stats.std,
            "count": stats.count,
            "artifacts": ["contoursImage": overlayURL?.path as Any]
        ]
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.vision.contours", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.vision.contours", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    func detectBarcodes(_ input: Operations.detectBarcodes.Input) async throws -> Operations.detectBarcodes.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var imgData: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .imagePng(let w): imgData = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = imgData, let cg = CGImage.fromPNGData(d) else { return .undocumented(statusCode: 400, .init()) }
        let (payloads, types) = try PBVRTHandlers.decodeBarcodes(cgImage: cg)
        let res = Components.Schemas.BarcodesResult(payloads: payloads, types: types)
        let payload: [String: Any] = ["payloads": payloads, "types": types]
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.vision.barcodes", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.vision.barcodes", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    // MARK: - Audio probes (stubs/minimal)
    func compareAudioEmbedding(_ input: Operations.compareAudioEmbedding.Input) async throws -> Operations.compareAudioEmbedding.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var bw: Data?; var cw: Data?; var backend: String = "yamnet"; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .baselineWav(let w): bw = try await collectBody(w.payload.body)
            case .candidateWav(let w): cw = try await collectBody(w.payload.body)
            case .backend(let w):
                if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { backend = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .undocumented: break
            }
        }
        guard let bd = bw, let cd = cw, let (bmono, bsr) = try? Self.decodeWavToMono(data: bd), let (cmono, csr) = try? Self.decodeWavToMono(data: cd) else {
            return .undocumented(statusCode: 400, .init())
        }
        let t0 = Date()
        // Attempt Core ML embedding; fallback to spectrogram flatten
        let (bvec, cvec, modelName, usedBackend) = Self.computeAudioEmbeddingPair(b: bmono, c: cmono, srB: bsr, srC: csr, preferredBackend: backend)
        let cos = Self.cosineDistance(a: bvec, b: cvec)
        let ms = Date().timeIntervalSince(t0) * 1000
        let res = Components.Schemas.AudioEmbeddingResult(metricName: .audio_embedding_cosine, value: Float(cos), backend: .init(rawValue: usedBackend) ?? .yamnet, model: modelName, durationMs: Float(ms))
        let payload: [String: Any] = [
            "backend": usedBackend,
            "model": modelName,
            "value": cos,
            "durationMs": ms
        ]
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.audio.embedding", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.audio.embedding", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    func compareSpectrogram(_ input: Operations.compareSpectrogram.Input) async throws -> Operations.compareSpectrogram.Output {
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var bw: Data?; var cw: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
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
        let payload: [String: Any] = [
            "l2": l2,
            "lsd_db": lsd,
            "artifacts": [
                "baselineSpecPng": bPNG.path,
                "candidateSpecPng": cPNG.path,
                "deltaSpecPng": dPNG.path
            ]
        ]
        if let bId = baselineId, !bId.isEmpty { await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.audio.spectrogram", payload: payload) }
        else { await core.writeAdHocSummary(kind: "pbvrt.audio.spectrogram", payload: payload) }
        return .ok(.init(body: .json(res)))
    }

    func detectOnsets(_ input: Operations.detectOnsets.Input) async throws -> Operations.detectOnsets.Output {
        let __dbg = ProcessInfo.processInfo.environment["PBVRT_DEBUG"] == "1"
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] detectOnsets: begin\n".utf8)) }
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var wav: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .wav(let w): wav = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = wav, let (mono, sr) = try? Self.decodeWavToMono(data: d) else {
            if __dbg { FileHandle.standardError.write(Data("[pbvrt] detectOnsets: bad wav decode\n".utf8)) }
            return .undocumented(statusCode: 400, .init())
        }
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] detectOnsets: samples=\(mono.count) sr=\(sr)\n".utf8)) }
        let hop = 512
        let win = 1024
        let (_, _, onsets) = Self.computeOnsets(samples: mono, sampleRate: sr, window: win, hop: hop)
        let tempo = Self.estimateTempo(onsets: onsets)
        let res = Components.Schemas.OnsetsResult(onsetsSec: onsets.map { Float($0) }, tempoBpm: tempo.map { Float($0) })
        if let bId = baselineId, !bId.isEmpty {
            await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.audio.onsets", payload: [
                "onsetsSec": onsets,
                "tempoBpm": tempo as Any
            ].compactMapValues { $0 })
        }
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] detectOnsets: ok\n".utf8)) }
        return .ok(.init(body: .json(res)))
    }

    func analyzePitch(_ input: Operations.analyzePitch.Input) async throws -> Operations.analyzePitch.Output {
        let __dbg = ProcessInfo.processInfo.environment["PBVRT_DEBUG"] == "1"
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzePitch: begin\n".utf8)) }
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var wav: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .wav(let w): wav = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = wav, let (mono, sr) = try? Self.decodeWavToMono(data: d) else {
            if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzePitch: bad wav decode\n".utf8)) }
            return .undocumented(statusCode: 400, .init())
        }
        let f0 = Self.autocorrPitchTrack(samples: mono, sampleRate: sr)
        let res = Components.Schemas.PitchResult(f0Hz: f0.map { Float($0) }, centsErrorMean: nil)
        if let bId = baselineId, !bId.isEmpty {
            await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.audio.pitch", payload: ["f0Hz": f0])
        }
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzePitch: ok\n".utf8)) }
        return .ok(.init(body: .json(res)))
    }

    func analyzeLoudness(_ input: Operations.analyzeLoudness.Input) async throws -> Operations.analyzeLoudness.Output {
        let __dbg = ProcessInfo.processInfo.environment["PBVRT_DEBUG"] == "1"
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzeLoudness: begin\n".utf8)) }
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var wav: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .wav(let w): wav = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let d = wav, let (mono, _) = try? Self.decodeWavToMono(data: d) else {
            if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzeLoudness: bad wav decode\n".utf8)) }
            return .undocumented(statusCode: 400, .init())
        }
        let (rms, meanDb, maxDb) = Self.loudnessEnvelope(samples: mono)
        let res = Components.Schemas.LoudnessResult(rms: rms.map { Float($0) }, meanDb: Float(meanDb), maxDb: Float(maxDb))
        if let bId = baselineId, !bId.isEmpty {
            await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.audio.loudness", payload: [
                "rms": rms,
                "meanDb": meanDb,
                "maxDb": maxDb
            ])
        }
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzeLoudness: ok\n".utf8)) }
        return .ok(.init(body: .json(res)))
    }

    func analyzeAlignment(_ input: Operations.analyzeAlignment.Input) async throws -> Operations.analyzeAlignment.Output {
        let __dbg = ProcessInfo.processInfo.environment["PBVRT_DEBUG"] == "1"
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzeAlignment: begin\n".utf8)) }
        guard case let .multipartForm(form) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var bw: Data?; var cw: Data?; var baselineId: String?
        for try await part in form {
            switch part {
            case .baselineId(let w): if let s = try? String(decoding: await collectBody(w.payload.body), as: UTF8.self) { baselineId = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .baselineWav(let w): bw = try await collectBody(w.payload.body)
            case .candidateWav(let w): cw = try await collectBody(w.payload.body)
            case .undocumented: break
            }
        }
        guard let bd = bw, let cd = cw,
              let (bmono, bsr) = try? Self.decodeWavToMono(data: bd),
              let (cmono, csr) = try? Self.decodeWavToMono(data: cd) else {
            if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzeAlignment: bad wav decode\n".utf8)) }
            return .undocumented(statusCode: 400, .init())
        }
        let sr = min(bsr, csr)
        let (offsetSamples, _) = Self.crossCorrelationOffset(a: bmono, b: cmono, sampleRate: sr)
        let offsetMs = (Double(offsetSamples) / sr) * 1000.0
        let res = Components.Schemas.AlignmentResult(offsetMs: Float(offsetMs), driftMs: nil)
        if let bId = baselineId, !bId.isEmpty {
            await core.writeBaselineSummary(baselineId: bId, kind: "pbvrt.audio.alignment", payload: [
                "offsetMs": offsetMs
            ])
        }
        if __dbg { FileHandle.standardError.write(Data("[pbvrt] analyzeAlignment: ok\n".utf8)) }
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
    static func estimateTranslationAround(baseline: CGImage, candidate: CGImage, sample: Int, centerDX: Int, centerDY: Int, window: Int) -> (dx: Int, dy: Int, score: Float) {
        guard let bSmall = baseline.resized(width: sample, height: sample), let cSmall = candidate.resized(width: sample, height: sample) else { return (centerDX,centerDY,0) }
        let b = grayscaleFloat(image: bSmall)
        let c = grayscaleFloat(image: cSmall)
        var bestScore: Float = .greatestFiniteMagnitude
        var best = (centerDX, centerDY)
        for dy in (centerDY - window)...(centerDY + window) {
            for dx in (centerDX - window)...(centerDX + window) {
                let s = sad(b: b, c: c, width: sample, height: sample, dx: dx, dy: dy)
                if s < bestScore { bestScore = s; best = (dx, dy) }
            }
        }
        return (best.0, best.1, bestScore)
    }
    static func refineTranslation(baseline: CGImage, candidate: CGImage, coarseDX: Int, coarseDY: Int, coarseSample: Int, refineSample: Int, window: Int) -> (dx: Int, dy: Int, score: Float) {
        // Scale coarse offset into refine sample space
        let sx = Double(refineSample) / Double(coarseSample)
        let rx = Int(round(Double(coarseDX) * sx))
        let ry = Int(round(Double(coarseDY) * sx))
        let (dx, dy, sc) = estimateTranslationAround(baseline: baseline, candidate: candidate, sample: refineSample, centerDX: rx, centerDY: ry, window: window)
        return (dx, dy, sc)
    }
    static func grayscaleFloat(image: CGImage) -> [Float] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w*h)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: 0) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data.map { Float($0) / 255.0 }
    }
    // Simple saliency map from gradient magnitude (Sobel-like) over grayscale input
    static func saliencyMap(fromGrayscale g: [Float], width: Int, height: Int) -> [Float] {
        if g.isEmpty { return [] }
        var out = [Float](repeating: 0, count: width*height)
        let kx: [[Float]] = [[-1,0,1],[-2,0,2],[-1,0,1]]
        let ky: [[Float]] = [[-1,-2,-1],[0,0,0],[1,2,1]]
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                var gx: Float = 0, gy: Float = 0
                for j in -1...1 {
                    for i in -1...1 {
                        let v = g[(y+j)*width + (x+i)]
                        gx += v * kx[j+1][i+1]
                        gy += v * ky[j+1][i+1]
                    }
                }
                let mag = sqrt(gx*gx + gy*gy)
                out[y*width + x] = mag
            }
        }
        // Normalize to 0..1
        var maxv: Float = out.max() ?? 1
        if maxv <= 1e-6 { maxv = 1 }
        for i in 0..<(width*height) { out[i] = out[i] / maxv }
        return out
    }
    static func visionSaliencyMap(cgImage: CGImage) throws -> [Float] {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first as? VNSaliencyImageObservation else {
            throw NSError(domain: "pbvrt", code: -2)
        }
        let heat: CVPixelBuffer = result.pixelBuffer
        // Convert CVPixelBuffer grayscale (0..1) to [Float]
        CVPixelBufferLockBaseAddress(heat, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(heat, .readOnly) }
        let w = CVPixelBufferGetWidth(heat)
        let h = CVPixelBufferGetHeight(heat)
        var out = [Float](repeating: 0, count: w*h)
        guard let base = CVPixelBufferGetBaseAddress(heat) else { return out }
        let fmt = CVPixelBufferGetPixelFormatType(heat)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(heat)
        if fmt == kCVPixelFormatType_OneComponent8 {
            for y in 0..<h {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<w { out[y*w + x] = Float(row[x]) / 255.0 }
            }
        } else if fmt == kCVPixelFormatType_OneComponent32Float {
            for y in 0..<h {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in 0..<w { let v = row[x]; out[y*w + x] = max(0, min(1, v)) }
            }
        } else {
            // Fallback: treat as 8-bit stride
            for y in 0..<h {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<w { out[y*w + x] = Float(row[x]) / 255.0 }
            }
        }
        return out
    }

    /// Weighted SSIM over the entire image using provided weights in 0..1.
    /// Uses the standard SSIM constants with L=1 (images normalized to 0..1).
    static func weightedSSIM(a: [Float], b: [Float], weight: [Float], count: Int) -> Double {
        let n = min(count, min(a.count, min(b.count, weight.count)))
        if n == 0 { return 1.0 }
        var sumW: Double = 0
        var sumAx: Double = 0, sumBx: Double = 0
        for i in 0..<n {
            let w = Double(weight[i])
            sumW += w
            sumAx += w * Double(a[i])
            sumBx += w * Double(b[i])
        }
        if sumW <= 0 { return 1.0 }
        let muA = sumAx / sumW
        let muB = sumBx / sumW
        var varA: Double = 0, varB: Double = 0, covAB: Double = 0
        for i in 0..<n {
            let w = Double(weight[i])
            let da = Double(a[i]) - muA
            let db = Double(b[i]) - muB
            varA += w * da * da
            varB += w * db * db
            covAB += w * da * db
        }
        varA /= sumW
        varB /= sumW
        covAB /= sumW
        let L: Double = 1.0
        let C1 = pow(0.01 * L, 2)
        let C2 = pow(0.03 * L, 2)
        let num = (2 * muA * muB + C1) * (2 * covAB + C2)
        let den = (muA * muA + muB * muB + C1) * (varA + varB + C2)
        if den == 0 { return 1.0 }
        return max(0.0, min(1.0, num / den))
    }

    struct ContourStats { let mean: Double; let std: Double; let count: Int }
    static func contoursStatsAndOverlay(cgImage: CGImage) throws -> (ContourStats, URL?) {
        let req = VNDetectContoursRequest()
        req.detectsDarkOnLight = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([req])
        guard let obs = req.results?.first as? VNContoursObservation else {
            return (ContourStats(mean: 0, std: 0, count: 0), nil)
        }
        // Compute vertical spacing between contour centroids
        var ys: [Double] = []
        for i in 0..<obs.contourCount {
            if let c = try? obs.contour(at: i) {
                let pts = c.normalizedPoints
                if pts.isEmpty { continue }
                let avgY = pts.map { Double($0.y) }.reduce(0, +) / Double(pts.count)
                ys.append(avgY)
            }
        }
        ys.sort()
        var spacings: [Double] = []
        for i in 1..<ys.count { spacings.append((ys[i] - ys[i-1]) * Double(cgImage.height)) }
        let count = ys.count
        let mean = spacings.isEmpty ? 0 : spacings.reduce(0, +) / Double(spacings.count)
        let varSum = spacings.reduce(0) { $0 + pow($1 - mean, 2) }
        let std = spacings.isEmpty ? 0 : sqrt(varSum / Double(spacings.count))
        // Render overlay
        let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(1)
        for i in 0..<obs.contourCount {
            if let c = try? obs.contour(at: i) {
                let pts = c.normalizedPoints
                if pts.count < 2 { continue }
                ctx.beginPath()
                for (idx, p) in pts.enumerated() {
                    let x = CGFloat(p.x) * CGFloat(cgImage.width)
                    let y = CGFloat(1 - p.y) * CGFloat(cgImage.height)
                    if idx == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.strokePath()
            }
        }
        let overlay = ctx.makeImage()
        var urlOut: URL? = nil
        if let overlay {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent("contours.png")
            try? overlay.writePNG(to: out)
            urlOut = out
        }
        return (ContourStats(mean: mean, std: std, count: count), urlOut)
    }

    static func decodeBarcodes(cgImage: CGImage) throws -> ([String], [String]) {
        let req = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([req])
        var payloads: [String] = []
        var types: [String] = []
        if let results = req.results as? [VNBarcodeObservation] {
            for r in results {
                if let s = r.payloadStringValue { payloads.append(s) }
                types.append(r.symbology.rawValue)
            }
        }
        return (payloads, types)
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
    static func cosineDistance(a: [Float], b: [Float]) -> Double {
        let n = min(a.count, b.count)
        if n == 0 { return 1.0 }
        var dot: Double = 0, na: Double = 0, nb: Double = 0
        for i in 0..<n {
            let x = Double(a[i]), y = Double(b[i])
            dot += x*y; na += x*x; nb += y*y
        }
        let denom = (sqrt(na) * sqrt(nb))
        if denom == 0 { return 1.0 }
        let cosSim = dot / denom
        return max(0.0, min(2.0, 1.0 - cosSim))
    }

    static func computeAudioEmbeddingPair(b: [Float], c: [Float], srB: Double, srC: Double, preferredBackend: String) -> ([Float],[Float], String, String) {
        // Try Core ML if model path configured
        if let path = ProcessInfo.processInfo.environment["PBVRT_AUDIO_EMBED_MODEL"], !path.isEmpty,
           let loaded = try? CoreMLInterop.loadModel(at: path) {
            let summary = ModelInfo.summarize(loaded.model)
            let input = summary.inputs.first
            let outName = summary.outputs.first?.name
            func prep(_ x: [Float], sr: Double) -> [Float] {
                let need = input?.shape.reduce(1, *) ?? x.count
                return resize1D(x, to: need)
            }
            let bin = prep(b, sr: srB)
            let cin = prep(c, sr: srC)
            var inputName = input?.name ?? "input"
            // MultiArray input assumed; shape 1D
            if let arrB = try? CoreMLInterop.makeMultiArray(bin, shape: [bin.count]),
               let arrC = try? CoreMLInterop.makeMultiArray(cin, shape: [cin.count]) {
                if let name = input?.name { inputName = name }
                let outB = (try? CoreMLInterop.predict(model: loaded.model, inputs: [inputName: arrB])) ?? [:]
                let outC = (try? CoreMLInterop.predict(model: loaded.model, inputs: [inputName: arrC])) ?? [:]
                if let on = outName, let vb = outB[on], let vc = outC[on] {
                    return (CoreMLInterop.toArray(vb), CoreMLInterop.toArray(vc), loaded.url.lastPathComponent, "coreml")
                }
                if let vb = outB.values.first, let vc = outC.values.first {
                    return (CoreMLInterop.toArray(vb), CoreMLInterop.toArray(vc), loaded.url.lastPathComponent, "coreml")
                }
            }
        }
        // Fallback: flatten coarse spectrogram as embedding
        let sr = min(srB, srC)
        let (bs, _) = spectrogram(samples: b, sampleRate: sr)
        let (cs, _) = spectrogram(samples: c, sampleRate: sr)
        let rows = min(bs.rows, cs.rows), cols = min(bs.cols, cs.cols)
        var bv: [Float] = []; bv.reserveCapacity(rows*cols)
        var cv: [Float] = []; cv.reserveCapacity(rows*cols)
        for j in 0..<cols { for i in 0..<rows { bv.append(bs.data[i*bs.cols + j]); cv.append(cs.data[i*cs.cols + j]) } }
        return (bv, cv, "coarse-spectrogram", "yamnet")
    }
    static func resize1D(_ x: [Float], to m: Int) -> [Float] {
        if x.count == m { return x }
        if x.isEmpty { return [Float](repeating: 0, count: m) }
        var out = [Float](repeating: 0, count: m)
        let scale = Double(x.count - 1) / Double(max(1, m - 1))
        for i in 0..<m {
            let pos = Double(i) * scale
            let i0 = Int(pos)
            let frac = Float(pos - Double(i0))
            let i1 = min(i0 + 1, x.count - 1)
            out[i] = x[i0] * (1 - frac) + x[i1] * frac
        }
        return out
    }
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

    // MARK: - Audio DSP helpers
    static func rmsFrames(samples: [Float], window: Int, hop: Int) -> [Double] {
        if samples.isEmpty || window <= 0 || hop <= 0 { return [] }
        let n = samples.count
        let frames = max(0, (n - window) / hop + 1)
        var out = [Double](repeating: 0, count: frames)
        for f in 0..<frames {
            let start = f * hop
            var sum: Double = 0
            for i in 0..<window { let v = Double(samples[start + i]); sum += v*v }
            out[f] = sqrt(sum / Double(window))
        }
        return out
    }
    static func computeOnsets(samples: [Float], sampleRate: Double, window: Int, hop: Int) -> (novelty: [Double], times: [Double], onsets: [Double]) {
        let rms = rmsFrames(samples: samples, window: window, hop: hop)
        if rms.isEmpty { return ([], [], []) }
        var novelty = [Double](repeating: 0, count: rms.count)
        novelty[0] = 0
        for i in 1..<rms.count { novelty[i] = max(0, rms[i] - rms[i-1]) }
        // Simple threshold: median + small factor
        let med = median(novelty)
        let thresh = med + 0.05
        var peaks: [Int] = []
        for i in 1..<(novelty.count-1) {
            if novelty[i] > thresh && novelty[i] > novelty[i-1] && novelty[i] >= novelty[i+1] { peaks.append(i) }
        }
        let times = (0..<novelty.count).map { Double($0 * hop) / sampleRate }
        let onsets = peaks.map { Double($0 * hop) / sampleRate }
        return (novelty, times, onsets)
    }
    static func estimateTempo(onsets: [Double]) -> Double? {
        if onsets.count < 2 { return nil }
        var ioi: [Double] = []
        for i in 1..<onsets.count { ioi.append(onsets[i] - onsets[i-1]) }
        let med = median(ioi)
        if med <= 0 { return nil }
        return 60.0 / med
    }
    static func median(_ x: [Double]) -> Double {
        if x.isEmpty { return 0 }
        let s = x.sorted(); let n = s.count
        if n % 2 == 1 { return s[n/2] }
        return 0.5 * (s[n/2-1] + s[n/2])
    }
    static func autocorrPitchTrack(samples: [Float], sampleRate: Double, window: Int = 1024, hop: Int = 512, fmin: Double = 80.0, fmax: Double = 800.0) -> [Double] {
        if samples.isEmpty { return [] }
        let n = samples.count
        let frames = max(0, (n - window) / hop + 1)
        var f0 = [Double](repeating: 0, count: frames)
        let minLag = max(1, Int(sampleRate / fmax))
        let maxLag = max(minLag+1, Int(sampleRate / fmin))
        for f in 0..<frames {
            let start = f * hop
            // windowed frame (Hann)
            var w = [Double](repeating: 0, count: window)
            for i in 0..<window {
                let hann = 0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(window))
                w[i] = Double(samples[start + i]) * hann
            }
            // autocorr over lag range
            var bestLag = minLag
            var bestVal = -Double.infinity
            for lag in minLag..<min(maxLag, window) {
                var sum: Double = 0
                for i in 0..<(window - lag) { sum += w[i] * w[i+lag] }
                if sum > bestVal { bestVal = sum; bestLag = lag }
            }
            f0[f] = sampleRate / Double(bestLag)
        }
        return f0
    }
    static func loudnessEnvelope(samples: [Float], window: Int = 1024, hop: Int = 512) -> ([Double], Double, Double) {
        let rms = rmsFrames(samples: samples, window: window, hop: hop)
        let db = rms.map { 20.0 * log10(max(1e-6, $0)) }
        let mean = db.isEmpty ? 0 : db.reduce(0, +) / Double(db.count)
        let maxv = db.max() ?? 0
        return (db, mean, maxv)
    }
    static func crossCorrelationOffset(a: [Float], b: [Float], sampleRate: Double, maxLagSec: Double = 0.25) -> (lagSamples: Int, value: Double) {
        // limit search to ±maxLag
        let maxLag = Int(maxLagSec * sampleRate)
        let n = min(a.count, b.count)
        var bestLag = 0
        var bestVal = -Double.infinity
        // Centered cross-corr: for lag L, compare a[i] with b[i+L]
        for lag in -maxLag...maxLag {
            var sum: Double = 0
            let startA = max(0, -lag)
            let startB = max(0, lag)
            let count = min(n - startA, n - startB)
            if count <= 0 { continue }
            for i in 0..<count { sum += Double(a[startA + i]) * Double(b[startB + i]) }
            if sum > bestVal { bestVal = sum; bestLag = lag }
        }
        return (bestLag, bestVal)
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
