import SwiftUI

struct Midi2MonitorOverlay: View {
    @Binding var isHot: Bool
    @State private var targetOpacity: Double = 1.0
    @State private var lastEvent: Date? = nil
    @State private var count: Int = 0

    private func startFade() {
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            targetOpacity = 0.08
        }
    }
    private func stopFade() {
        withAnimation(.easeOut(duration: 0.12)) { targetOpacity = 1.0 }
    }

    var body: some View {
        let recent = (lastEvent?.timeIntervalSinceNow ?? -999) > -2.0
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(recent ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("MIDI 2.0 Monitor")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text("events \(count)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(targetOpacity)
        .onAppear { if !isHot { startFade() } }
        .onChange(of: isHot) { _, hot in hot ? stopFade() : startFade() }
        .onReceive(NotificationCenter.default.publisher(for: .MetalCanvasMIDIActivity)) { _ in
            lastEvent = Date(); count += 1
        }
    }
}

