import SwiftUI

struct FountainEditorWindow: View {
    @StateObject private var model = FountainEditorModel()
    @State private var selection: FountainEditorModel.Scene?
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            OutlineView(model: model, selection: $selection)
                .frame(minWidth: 220)
        } content: {
            ZStack(alignment: .bottom) {
                if model.mode == .editor {
                    TextEditor(text: Binding(get: { model.text }, set: { model.onChangeText($0) }))
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .focused($editorFocused)
                } else {
                    VStack(spacing: 12) {
                        Text("Chat mode (stub)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Draft, rewrite, and placements tools will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                StatusBar(model: model)
            }
        } detail: {
            DrawerView()
                .frame(minWidth: 260)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Picker("Corpus", selection: $model.corpusId) {
                    Text(model.corpusId).tag(model.corpusId)
                }.labelsHidden()
            }
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { model.toggleMode() }) {
                    Image(systemName: model.mode == .editor ? "text.book.closed" : "bubble.left.and.bubble.right")
                }.help("Toggle Editor/Chat (Cmd+\\)")
                Button(action: { Task { await model.save() } }) {
                    Image(systemName: "tray.and.arrow.down")
                }.help("Save (Cmd+S)")
            }
        }
        .onAppear { editorFocused = true }
    }

    private struct OutlineView: View {
        @ObservedObject var model: FountainEditorModel
        @Binding var selection: FountainEditorModel.Scene?
        var body: some View {
            List(selection: $selection) {
                ForEach(model.acts) { act in
                    Section(header: Text("ACT \(act.index): \(act.title)")) {
                        ForEach(act.scenes) { scene in
                            Text("Scene \(scene.index): \(scene.title)")
                                .tag(scene as FountainEditorModel.Scene?)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private struct StatusBar: View {
        @ObservedObject var model: FountainEditorModel
        var body: some View {
            HStack(spacing: 16) {
                Text("ETag \(model.etag)").monospaced().foregroundStyle(.secondary)
                Divider()
                Text("Acts: \(model.acts.count)").foregroundStyle(.secondary)
                Text("Scenes: \(model.acts.map{ $0.scenes.count }.reduce(0,+))").foregroundStyle(.secondary)
                Spacer()
                if model.isSaving { ProgressView().scaleEffect(0.7) }
                if let t = model.lastSavedAt {
                    Text("Saved \(t.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
    }

    private struct DrawerView: View {
        @State private var tab: Int = 0
        var body: some View {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Placements").tag(0)
                    Text("Library").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(8)
                if tab == 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Placements (stub)").font(.headline)
                        Text("Add/update/remove placements anchored to scenes.").foregroundStyle(.secondary)
                        Spacer()
                    }.padding(8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Library (stub)").font(.headline)
                        Text("Manage midi2sampler instruments, tags, profiles.").foregroundStyle(.secondary)
                        Spacer()
                    }.padding(8)
                }
            }
        }
    }
}
