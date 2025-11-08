import SwiftUI

struct FountainEditorSurface: View {
    let frameSize: CGSize
    @StateObject private var model = FountainEditorModel()
    @FocusState private var editorFocused: Bool

    private let sidebarWidth: CGFloat = 240
    private let pageInset: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            // Outline (acts/scenes)
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTS / SCENES").font(.caption).foregroundStyle(.secondary)
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
                .listStyle(.sidebar)
            }
            .padding(.top, 8)
            .frame(width: sidebarWidth)
            .background(Color(NSColor.underPageBackgroundColor))

            // Page area
            ZStack(alignment: .bottom) {
                QuietFrameShape()
                    .fill(Color.white)
                    .overlay(QuietFrameShape().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                    .frame(width: frameSize.width, height: frameSize.height)

                // Editor content with margins
                TextEditor(text: Binding(get: { model.text }, set: { model.onChangeText($0) }))
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, pageInset)
                    .padding(.vertical, pageInset)
                    .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
                    .focused($editorFocused)

                StatusBar(model: model)
            }
            .frame(width: frameSize.width, height: frameSize.height)

            // Right drawer placeholder for future instruments/library
            VStack(alignment: .leading, spacing: 8) {
                Text("Drawer").font(.caption).foregroundStyle(.secondary)
                Text("Placements / Library (stub)").foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 260)
            .background(Color(NSColor.underPageBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { editorFocused = true }
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

