import SwiftUI
import AppKit

@main
struct QuietFrameCompanionApp: App {
    var body: some Scene {
        WindowGroup("QuietFrame Companion") {
            CompanionRootView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

struct CompanionRootView: View {
    @StateObject private var recorder = MP4ScreenRecorder()
    @StateObject private var pe = QuietFramePEClient()
    var body: some View {
        HStack(spacing: 0) {
            // Left: Placeholder for PE inspector controls (future)
            VStack(alignment: .leading) {
                HStack {
                    Text("PE Inspector").font(.headline)
                    Spacer()
                    Button("Connect") { pe.connect() }
                }
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("Master").font(.caption)
                            Slider(value: Binding(get: { 0.8 }, set: { pe.set([("engine.masterGain", $0)]) }), in: 0...1)
                                .frame(width: 160)
                        }
                        GridRow {
                            Text("Mute").font(.caption)
                            Toggle("", isOn: Binding(get: { false }, set: { pe.set([("audio.muted", $0 ? 1.0 : 0.0)]) }))
                                .toggleStyle(.switch)
                        }
                        GridRow {
                            Button("GET Snapshot") { pe.get() }
                        }
                    }
                } label: { Text(pe.connectedName ?? "Not connected").font(.caption) }
                TextEditor(text: $pe.lastSnapshotJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 140)
                Spacer()
            }
            .padding(12)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
            // Right: Player and Recorder
            PlayerPaneView(recorder: recorder)
                .onAppear {
                    recorder.start(targetWindowTitle: "QuietFrame Sonify")
                    pe.eventSink = { [weak recorder] json in recorder?.appendMidiEvent(json: json) }
                }
        }
        .frame(minWidth: 1024, minHeight: 600)
    }
}
