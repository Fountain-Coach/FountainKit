import Foundation
import OpenAPIRuntime
import FountainStoreClient

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
        let artifacts: [String: String] = [
            "baselinePng": baselineDir(baselineId).appendingPathComponent("baseline.png").path,
            "embeddingJson": baselineDir(baselineId).appendingPathComponent("embedding.json").path,
            "midiUmp": baselineDir(baselineId).appendingPathComponent("sequence.ump").path
        ]
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
        let report = Components.Schemas.DriftReport(
            baselineId: bId,
            metrics: .init(pixel_l1: 0, ssim: 1, featureprint_distance: nil, clip_cosine: nil, prompt_cosine: nil),
            pass: true,
            artifacts: .init(candidatePng: candidateURL.path, deltaPng: nil),
            timestamps: .init(baseline: nil, run: Date())
        )
        return .ok(.init(body: .json(report)))
    }

    // POST /probes/embedding/compare (stub)
    func compareEmbeddingAdhoc(_ input: Operations.compareEmbeddingAdhoc.Input) async throws -> Operations.compareEmbeddingAdhoc.Output {
        // Not implemented; return 200 with zero distance
        let out = Components.Schemas.EmbeddingResult(metricName: .featureprint_distance, value: 0, backend: .featurePrint, model: "featurePrint", durationMs: 0)
        return .ok(.init(body: .json(out)))
    }
    // Helpers
    private func collectBody(_ body: OpenAPIRuntime.HTTPBody) async throws -> Data {
        try await Data(collecting: body, upTo: 1 << 22)
    }
}
