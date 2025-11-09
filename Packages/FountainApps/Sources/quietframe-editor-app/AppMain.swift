import SwiftUI
import Foundation
import FountainStoreClient

@main
struct QuietFrameEditorApp: App {
    init() {
        // Print Teatro prompt on boot (no seeding here; read-only)
        Task { await TeatroPrinter.printOnBoot() }
    }
    var body: some Scene {
        WindowGroup("QuietFrame — Fountain Editor") {
            EditorLandingView()
        }
        .windowStyle(.automatic)
    }
}

enum TeatroPrinter {
    static func printOnBoot() async {
        do {
            let env = ProcessInfo.processInfo.environment
            let corpusId = env["QUIETFRAME_CORPUS_ID"] ?? "quietframe"
            let store = resolveStore()
            // Fetch teatro.prompt segment text
            if let data = try await store.getDoc(corpusId: corpusId, collection: "segments", id: "prompt:\(corpusId):teatro"),
               let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = obj["text"] as? String {
                print("\n=== Teatro Prompt (\(corpusId)) ===\n\(text)\n=== end prompt ===\n")
            }
        } catch {
            // Best effort: do not crash app if store not available
        }
    }

    private static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }
}

final class EditorModel: ObservableObject {
    @Published var corpusId: String = ProcessInfo.processInfo.environment["CORPUS_ID"] ?? "fountain-editor"
    @Published var text: String = ""
    @Published var etag: String = ""
    @Published var outline: [Act] = []
    @Published var status: String = ""
    @Published var isSaving: Bool = false

    struct Beat: Codable, Identifiable { let index: Int; let title: String; var id: Int { index } }
    struct Scene: Codable, Identifiable { let index: Int; let title: String; let beats: [Beat]; var id: Int { index } }
    struct Act: Codable, Identifiable { let index: Int; let title: String; let scenes: [Scene]; var id: Int { index } }
    struct StructureDTO: Codable { let etag: String; let acts: [Act] }

    private var baseURL: URL { URL(string: ProcessInfo.processInfo.environment["EDITOR_URL"] ?? "http://127.0.0.1:8080")! }

    @MainActor
    func load() async {
        let env = ProcessInfo.processInfo.environment
        if let seed = env["EDITOR_SEED_TEXT"], !seed.isEmpty {
            // Offline seeded mode for snapshots/tests
            self.text = seed
            self.etag = EditorModel.computeETag(seed)
            self.outline = EditorModel.parseStructure(seed)
            self.status = "Ready"
            return
        }
        status = "Loading…"
        do {
            try await fetchScript()
            try await fetchStructure()
            status = "Ready"
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    func reloadStructurePreview() async {
        do { try await fetchStructure() } catch { /* ignore preview errors */ }
    }

    @MainActor
    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        status = "Saving…"
        do {
            var req = URLRequest(url: baseURL.appendingPathComponent("/editor/\(corpusId)/script"))
            req.httpMethod = "PUT"
            req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            req.setValue(etag.isEmpty ? "*" : etag, forHTTPHeaderField: "If-Match")
            req.httpBody = Data(text.utf8)
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 204 {
                status = "Saved"
                try await fetchScript()
                try await fetchStructure()
            } else if http.statusCode == 412 {
                status = "Save blocked (ETag mismatch)"
            } else {
                status = "Save failed (\(http.statusCode))"
            }
        } catch {
            status = "Save error: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func fetchScript() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/editor/\(corpusId)/script"))
        req.httpMethod = "GET"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 200 {
            self.text = String(data: data, encoding: .utf8) ?? ""
            self.etag = http.value(forHTTPHeaderField: "ETag") ?? ""
        } else if http.statusCode == 404 {
            self.text = ""
            self.etag = ""
            self.status = "No script yet — type and Save to create."
        }
    }

    @MainActor
    private func fetchStructure() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/editor/\(corpusId)/structure"))
        req.httpMethod = "GET"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { self.outline = []; return }
        let dto = try JSONDecoder().decode(StructureDTO.self, from: data)
        self.outline = dto.acts
    }
}

struct EditorLandingView: View {
    @StateObject private var model = EditorModel()
    @State private var lastPreviewTask: Task<Void, Never>? = nil
    private let gutterWidth: CGFloat = 14
    @State private var totalSize: CGSize = .zero
    @State private var outlineWidth: CGFloat = 0
    @State private var editorWidth: CGFloat = 0
    @State private var drawerWidth: CGFloat = 0
    @State private var geometryDumped = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    // Outline (left)
                    outlinePane
                        .background(GeometryReader { gp in
                            Color.clear.onAppear { outlineWidth = gp.size.width }
                                .onChange(of: gp.size) { _, n in outlineWidth = n.width }
                        })
                    // Gutter between outline and editor
                    Divider().frame(width: gutterWidth)
                    // Editor (center)
                    editorPane
                        .background(GeometryReader { gp in
                            Color.clear.onAppear { editorWidth = gp.size.width }
                                .onChange(of: gp.size) { _, n in editorWidth = n.width }
                        })
                    // Gutter between editor and drawer (visual only)
                    Divider().frame(width: gutterWidth)
                    // Drawer (right)
                    drawerPane
                        .background(GeometryReader { gp in
                            Color.clear.onAppear { drawerWidth = gp.size.width }
                                .onChange(of: gp.size) { _, n in drawerWidth = n.width }
                        })
                }
                Divider()
                statusBar
            }
            .onAppear { totalSize = proxy.size; scheduleGeometryDump() }
            .onChange(of: proxy.size) { _, n in totalSize = n; scheduleGeometryDump() }
        }
        .task { await model.load() }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var header: some View {
        HStack {
            Text("Corpus:")
            TextField("corpus-id", text: $model.corpusId)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Spacer()
            Group {
                Text("ETag: \(model.etag.isEmpty ? "—" : model.etag)")
                    .monospaced().foregroundStyle(.secondary)
                Divider().frame(height: 14)
                Button(action: { lastPreviewTask?.cancel(); lastPreviewTask = Task { await model.load() } }) { Text("Reload") }
                Button(action: { lastPreviewTask?.cancel(); lastPreviewTask = Task { await model.save() } }) {
                    if model.isSaving { ProgressView().controlSize(.small) } else { Text("Save") }
                }.keyboardShortcut("s", modifiers: [.command])
            }
            Divider().frame(height: 14)
            Text(model.status).foregroundStyle(.secondary)
        }.padding(10)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fountain Script").font(.headline)
            TextEditor(text: $model.text)
                .font(.system(.body, design: .monospaced))
                .onChange(of: model.text) { _, _ in
                    lastPreviewTask?.cancel()
                    lastPreviewTask = Task { try? await Task.sleep(nanoseconds: 250_000_000); await model.reloadStructurePreview() }
                }
        }
        .padding(10)
        .frame(minWidth: 480)
    }

    private var outlinePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Structure").font(.headline)
            if model.outline.isEmpty {
                Text("No scenes detected.").foregroundStyle(.secondary)
            } else {
                List(model.outline) { act in
                    Section("Act \(act.index)") {
                        ForEach(act.scenes) { sc in
                            HStack {
                                Text("act\(act.index).scene\(sc.index)").monospaced().foregroundStyle(.secondary)
                                Text(sc.title).lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(10)
        .frame(minWidth: 220)
    }

    private var drawerPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instruments").font(.headline)
            TabView {
                // Library tab (placeholder; wired later to server data)
                VStack(alignment: .leading) {
                    if model.library.isEmpty {
                        Text("No library items.").foregroundStyle(.secondary)
                    } else {
                        List(model.library, id: \.instrumentId) { item in
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(item.profile).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.sidebar)
                    }
                }
                .tabItem { Label("Library", systemImage: "books.vertical") }
                // Placements tab (placeholder)
                VStack(alignment: .leading) {
                    if model.placements.isEmpty {
                        Text("No placements.").foregroundStyle(.secondary)
                    } else {
                        List(model.placements, id: \.placementId) { p in
                            HStack {
                                Text(p.anchor).monospaced().foregroundStyle(.secondary)
                                Text(p.instrumentId)
                            }
                        }
                        .listStyle(.sidebar)
                    }
                }
                .tabItem { Label("Placements", systemImage: "cube") }
            }
            .tabViewStyle(.automatic)
        }
        .padding(10)
        .frame(minWidth: 260)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("Corpus: \(model.corpusId)")
            Divider().frame(height: 12)
            Text("ETag: \(model.etag.isEmpty ? "—" : model.etag)").monospaced()
            Divider().frame(height: 12)
            Text("Words: \(model.wordCount)")
            Divider().frame(height: 12)
            Text("Pages: \(model.pageCount)")
            Spacer()
            Text(model.status).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func scheduleGeometryDump() {
        guard !geometryDumped else { return }
        if let path = ProcessInfo.processInfo.environment["EDITOR_GEOMETRY_DUMP"], !path.isEmpty {
            geometryDumped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let dict: [String: Any] = [
                    "total": ["w": totalSize.width, "h": totalSize.height],
                    "outlineWidth": outlineWidth,
                    "editorWidth": editorWidth,
                    "gutterWidth": gutterWidth
                ]
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
                   let url = URL(string: "file://" + path) {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: url)
                }
            }
        }
    }
}

// MARK: - Minimal local parser + ETag for offline seeded snapshots
extension EditorModel {
    static func computeETag(_ text: String) -> String {
        var hash: UInt32 = 0
        for b in text.utf8 { hash = (hash &* 16777619) ^ UInt32(b) }
        return String(format: "%08X", hash)
    }
    static func parseStructure(_ text: String) -> [Act] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var acts: [Act] = []
        var actIdx = 0
        var scenes: [Scene] = []
        var sceneIdx = 0
        func startAct() {
            if actIdx > 0 { acts.append(Act(index: actIdx, title: "ACT \(actIdx)", scenes: scenes)); scenes = []; sceneIdx = 0 }
            actIdx += 1
        }
        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("# ") && !s.hasPrefix("## ") { startAct(); continue }
            if s.hasPrefix("## ") {
                if actIdx == 0 { startAct() }
                sceneIdx += 1
                let title = String(s.dropFirst(3))
                scenes.append(Scene(index: sceneIdx, title: title, beats: []))
            }
        }
        if actIdx == 0 { actIdx = 1 }
        acts.append(Act(index: actIdx, title: "ACT \(actIdx)", scenes: scenes))
        return acts
    }
}

// MARK: - Drawer data shims (placeholder models)
extension EditorModel {
    struct LibraryItem: Identifiable { let instrumentId: String; let name: String; let profile: String; var id: String { instrumentId } }
    struct PlacementItem: Identifiable { let placementId: String; let anchor: String; let instrumentId: String; var id: String { placementId } }

    var library: [LibraryItem] { [] }
    var placements: [PlacementItem] { [] }
    var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    var pageCount: Int {
        // Rough approximation: 55 lines/page, recompute by line count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return max(1, Int(ceil(Double(lines) / 55.0)))
    }
}
