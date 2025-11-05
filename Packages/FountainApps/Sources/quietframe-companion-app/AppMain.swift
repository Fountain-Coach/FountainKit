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
    var body: some View {
        HStack(spacing: 0) {
            // Left: Placeholder for PE inspector controls (future)
            VStack(alignment: .leading) {
                Text("PE Inspector (coming soon)").font(.headline)
                Text("Connects to 'Quiet Frame' endpoint; exposes Engine/Drone/Clock/Breath/Overtones/FX/Act.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
            // Right: Player and Recorder
            PlayerPaneView(recorder: recorder)
        }
        .frame(minWidth: 1024, minHeight: 600)
    }
}

