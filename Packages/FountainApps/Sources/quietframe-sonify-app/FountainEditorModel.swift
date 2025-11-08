import Foundation
import SwiftUI
import FountainStoreClient
import Teatro

@MainActor
final class FountainEditorModel: ObservableObject {
    @Published var corpusId: String
    @Published var text: String = ""
    @Published var etag: String = ""
    @Published var acts: [Act] = []
    @Published var mode: Mode = .editor
    @Published var isSaving: Bool = false
    @Published var lastSavedAt: Date? = nil

    private let store: FountainStoreClient
    private let parser = FountainParser()
    private var parseTask: Task<Void, Never>? = nil

    enum Mode { case editor, chat }

    struct Act: Identifiable, Hashable { let id = UUID(); var title: String; var index: Int; var scenes: [Scene] }
    struct Scene: Identifiable, Hashable { let id = UUID(); var title: String; var index: Int }

    init(corpusId: String? = nil) {
        let env = ProcessInfo.processInfo.environment
        let cid = corpusId ?? env["CORPUS_ID"] ?? "fountain-editor"
        self.corpusId = cid
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")
        let disk = (try? DiskFountainStoreClient(rootDirectory: root))
        self.store = FountainStoreClient(client: disk ?? EmbeddedFountainStoreClient())
        Task { await loadInitial() }
    }

    func toggleMode() { mode = (mode == .editor ? .chat : .editor) }

    func loadInitial() async {
        do { _ = try await store.createCorpus(corpusId) } catch { }
        let scriptPage = "docs:\(corpusId):fountain:script"
        let scriptSeg = "\(scriptPage):doc"
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: scriptSeg),
           let s = String(data: data, encoding: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
           let txt = obj["text"] as? String {
            self.text = txt
        } else {
            self.text = "Title: Untitled\n\n# ACT I\n\nINT. ROOM — DAY\nA blank page.\n"
        }
        computeETag()
        reparse()
    }

    func onChangeText(_ newText: String) {
        self.text = newText
        computeETag()
        scheduleParse()
    }

    private func scheduleParse() {
        parseTask?.cancel()
        parseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self?.reparse()
        }
    }

    private func reparse() {
        let nodes = parser.parse(text)
        var actsOut: [Act] = []
        var actIndex = 0
        var sceneIndex = 0
        func pushAct(title: String) { actIndex += 1; sceneIndex = 0; actsOut.append(Act(title: title, index: actIndex, scenes: [])) }
        func pushScene(title: String) { sceneIndex += 1; if actsOut.isEmpty { pushAct(title: "ACT I") }; actsOut[actsOut.count-1].scenes.append(Scene(title: title, index: sceneIndex)) }
        for n in nodes {
            switch n.type {
            case .section(let level):
                if level == 1 { pushAct(title: n.rawText.trimmingCharacters(in: .whitespaces)) }
                else if level == 2 { pushScene(title: n.rawText.trimmingCharacters(in: .whitespaces)) }
            case .sceneHeading:
                pushScene(title: n.rawText.trimmingCharacters(in: .whitespaces))
            default: break
            }
        }
        if actsOut.isEmpty { pushAct(title: "ACT I") }
        self.acts = actsOut
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        let pageId = "docs:\(corpusId):fountain:script"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://\(pageId)", host: "store", title: "Fountain Script"))
        let scriptSeg = Segment(corpusId: corpusId, segmentId: "\(pageId):doc", pageId: pageId, kind: "doc", text: text)
        _ = try? await store.addSegment(scriptSeg)
        // Structure facts (lightweight)
        let structPage = "prompt:\(corpusId):fountain-structure"
        _ = try? await store.addPage(.init(corpusId: corpusId, pageId: structPage, url: "store://\(structPage)", host: "store", title: "Fountain Structure"))
        let facts: [String: Any] = [
            "etag": etag,
            "acts": acts.map { ["index": $0.index, "title": $0.title, "scenes": $0.scenes.map { ["index": $0.index, "title": $0.title] } ] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(structPage):facts", pageId: structPage, kind: "facts", text: text))
        }
        lastSavedAt = Date()
    }

    private func computeETag() {
        etag = String(format: "%08X", text.utf8.reduce(0) { ($0 &* 16777619) ^ UInt32($1) })
    }
}
