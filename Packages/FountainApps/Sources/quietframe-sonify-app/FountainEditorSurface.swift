import SwiftUI
import Foundation

struct FountainEditorSurface: View {
    let frameSize: CGSize
    @StateObject private var model = FountainEditorModel()
    @FocusState private var editorFocused: Bool

    private let sidebarWidth: CGFloat = 240
    private let pageInset: CGFloat = 48
    @State private var measuredSidebarWidth: CGFloat = 0
    @State private var measuredPageWidth: CGFloat = 0
    @State private var measuredPageHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            // Outline (acts/scenes)
            List {
                ForEach(model.acts) { act in
                    Section(header: Text("ACT \(act.index): \(act.title)")) {
                        ForEach(act.scenes) { s in
                            Text("Scene \(s.index): \(s.title)")
                                .font(.callout)
                        }
                    }
                }
            }
            .frame(width: sidebarWidth)
            .background(GeometryReader { gp in
                Color.clear
                    .onAppear { measuredSidebarWidth = gp.size.width }
                    .onChange(of: gp.size) { _, newV in measuredSidebarWidth = newV.width }
            })
            .listStyle(.sidebar)

            // Page area (clean white)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                    .frame(width: frameSize.width, height: frameSize.height)

                // Editor content with margins
                TextEditor(text: Binding(get: { model.text }, set: { model.onChangeText($0) }))
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .padding(.horizontal, pageInset)
                    .padding(.vertical, pageInset)
                    .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
                    .focused($editorFocused)

                StatusBar(model: model)
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .background(GeometryReader { gp in
                Color.clear
                    .onAppear { measuredPageWidth = gp.size.width; measuredPageHeight = gp.size.height }
                    .onChange(of: gp.size) { _, newV in measuredPageWidth = newV.width; measuredPageHeight = newV.height }
            })

            // Right drawer removed for minimal first slice
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { editorFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .SaveFountainScript)) { _ in
            Task { await model.save() }
        }
        .onAppear { scheduleGeometryDump() }
    }

    private func scheduleGeometryDump() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["QF_EDITOR_GEOMETRY_DUMP"], !path.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let dict: [String: Any] = [
                "sidebarWidth": measuredSidebarWidth,
                "pageWidth": measuredPageWidth,
                "pageHeight": measuredPageHeight
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let url = URL(string: "file://" + path) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
            }
        }
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
            if let t = model.lastSavedAt { Text("Saved \(t.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
