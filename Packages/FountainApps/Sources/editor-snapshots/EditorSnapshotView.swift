import SwiftUI

struct SnapshotEditorModel {
    var text: String
    var outline: [Act]

    struct Beat: Identifiable { let index: Int; let title: String; var id: Int { index } }
    struct Scene: Identifiable { let index: Int; let title: String; let beats: [Beat]; var id: Int { index } }
    struct Act: Identifiable { let index: Int; let title: String; let scenes: [Scene]; var id: Int { index } }

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

struct EditorSnapshotView: View {
    private let gutterWidth: CGFloat = 14
    private let outlineMinWidth: CGFloat = 320

    let model: SnapshotEditorModel

    init(seedText: String) {
        self.model = SnapshotEditorModel(text: seedText, outline: SnapshotEditorModel.parseStructure(seedText))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                editorPane
                Divider().frame(width: gutterWidth)
                outlinePane
            }
        }
    }

    private var header: some View {
        HStack {
            Text("QuietFrame — Fountain Editor (Snapshot)").font(.headline)
            Spacer()
            Text("ETag: —").monospaced().foregroundStyle(.secondary)
        }.padding(10)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fountain Script").font(.headline)
            ScrollView { Text(model.text).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
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
                }.listStyle(.inset)
            }
        }
        .padding(10)
        .frame(minWidth: outlineMinWidth)
    }
}

