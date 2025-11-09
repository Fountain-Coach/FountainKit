import SwiftUI

@main
struct QuietFrameEditorApp: App {
    var body: some Scene {
        WindowGroup("QuietFrame — Fountain Editor") {
            EditorLandingView()
        }
        .windowStyle(.automatic)
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                editorPane
                Divider()
                outlinePane
            }
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
        .frame(minWidth: 320)
    }
}
