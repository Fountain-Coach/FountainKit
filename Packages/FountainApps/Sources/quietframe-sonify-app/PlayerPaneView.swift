import SwiftUI
import AVKit

struct PlayerPaneView: View {
    @ObservedObject var recorder: MP4ScreenRecorder
    @State private var player: AVPlayer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Spacer()
            }
            Group {
                if recorder.isRecording, let img = recorder.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .border(Color.red.opacity(0.5))
                    Text(String(format: "%.1f s", recorder.duration)).font(.caption).foregroundStyle(.secondary)
                } else if let url = recorder.lastURL {
                    PlayerView(url: url, player: $player)
                        .frame(maxWidth: .infinity, maxHeight: 260)
                } else {
                    ZStack {
                        Color(NSColor.windowBackgroundColor)
                        Text("No recording yet").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 240)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button {
                    if let win = NSApp.mainWindow {
                        recorder.start(window: win, rect: win.frame)
                    }
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .disabled(!recorder.canRecord)
                .tint(.red)

                Button {
                    recorder.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(!recorder.canStop)

                Button {
                    recorder.saveAs()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!recorder.canSave)

                Spacer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding(10)
        .frame(width: 360)
        .background(.thinMaterial)
        .onChange(of: recorder.lastURL) { _, newURL in
            if let url = newURL { player = AVPlayer(url: url) }
        }
    }

    private var statusText: String {
        switch recorder.state {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .stopping: return "Stopping…"
        case .finished: return "Ready"
        }
    }
    private var statusIcon: String {
        switch recorder.state {
        case .idle: return "circle"
        case .recording: return "record.circle.fill"
        case .stopping: return "hourglass"
        case .finished: return "play.circle"
        }
    }
    private var statusColor: Color {
        switch recorder.state {
        case .recording: return .red
        case .stopping: return .orange
        default: return .secondary
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let url: URL
    @Binding var player: AVPlayer?
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = false
        v.player = player ?? AVPlayer(url: url)
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player == nil {
            nsView.player = player ?? AVPlayer(url: url)
        }
    }
}

