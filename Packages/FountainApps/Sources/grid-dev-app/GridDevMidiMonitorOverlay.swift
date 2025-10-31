import SwiftUI
import MetalViewKit

struct GridDevMidiMonitorOverlay: View {
    @Binding var isHot: Bool
    @State private var targetOpacity: Double = 1.0
    @State private var minOpacity: Double = 0.08
    @State private var fadeSeconds: Double = 4.0
    @State private var maxLines: Int = 12
    @State private var lastEvent: Date? = nil
    @State private var count: Int = 0
    @State private var events: [Event] = []
    @State private var fadeWork: DispatchWorkItem? = nil

    struct Event: Identifiable {
        let id = UUID().uuidString
        let time = Date()
        let text: String
        let color: Color
    }

    private func push(_ e: Event) { events.append(e); trim() }
    private func trim() { if events.count > maxLines { events.removeFirst(events.count - maxLines) } }

    private func formatEvent(_ info: [AnyHashable: Any]?) -> Event {
        let type = (info?["type"] as? String) ?? "?"
        switch type {
        case "noteOn":
            let g = info?["group"] as? Int ?? 0
            let c = info?["channel"] as? Int ?? 0
            let n = info?["note"] as? Int ?? 0
            let v = info?["velocity"] as? Int ?? 0
            return Event(text: String(format: "Grp%d Ch%d NoteOn %3d vel %3d", g, c, n, v), color: .green)
        case "cc":
            let g = info?["group"] as? Int ?? 0
            let c = info?["channel"] as? Int ?? 0
            let cc = info?["controller"] as? Int ?? 0
            let v = info?["value"] as? Int ?? 0
            return Event(text: String(format: "Grp%d Ch%d CC %3d = %3d", g, c, cc, v), color: .blue)
        case "pb":
            let g = info?["group"] as? Int ?? 0
            let c = info?["channel"] as? Int ?? 0
            let v = info?["value14"] as? Int ?? 0
            return Event(text: String(format: "Grp%d Ch%d PB %5d", g, c, v), color: .purple)
        case "pe.set":
            let name = info?["name"] as? String ?? "?"
            let val = info?["value"] as? Double ?? .nan
            return Event(text: String(format: "PE set %@ = %.3f", name, val), color: .orange)
        case "ui.zoom", "ui.zoom.debug":
            let z = info?["zoom"] as? Double ?? .nan
            return Event(text: String(format: "UI zoom %.2fx", z), color: .gray)
        case "ui.cursor.move":
            let gx = info?["grid.x"] as? Int ?? 0
            let gy = info?["grid.y"] as? Int ?? 0
            let vx = info?["view.x"] as? Int ?? 0
            let vy = info?["view.y"] as? Int ?? 0
            let dx = info?["doc.x"] as? Int ?? 0
            let dy = info?["doc.y"] as? Int ?? 0
            return Event(text: String(format: "cursor g:%d,%d  v:%d,%d  d:%d,%d", gx, gy, vx, vy, dx, dy), color: .primary)
        case "ui.pan", "ui.pan.debug":
            let x = info?["x"] as? Double ?? .nan
            let y = info?["y"] as? Double ?? .nan
            return Event(text: String(format: "UI pan x=%.0f y=%.0f", x, y), color: .gray)
        case "ci.discovery.reply":
            return Event(text: "CI discovery reply", color: .yellow)
        default:
            return Event(text: type, color: .secondary)
        }
    }

    private func startFade() { withAnimation(.linear(duration: fadeSeconds)) { targetOpacity = minOpacity } }
    private func stopFade() { withAnimation(.easeOut(duration: 0.12)) { targetOpacity = 1.0 } }
    private func scheduleFade() {
        fadeWork?.cancel()
        let w = DispatchWorkItem { startFade() }
        fadeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeSeconds, execute: w)
    }

    var body: some View {
        let recent = (lastEvent?.timeIntervalSinceNow ?? -999) > -2.0
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(recent ? Color.green : Color.gray).frame(width: 8, height: 8)
                Text("MIDI 2.0 Monitor").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(events) { e in
                    Text(e.text).font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundStyle(e.color)
                }
                Text("total \(count)").font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(targetOpacity)
        .onAppear { isHot ? stopFade() : startFade() }
        .onChange(of: isHot) { _, hot in
            if hot { stopFade() } else { scheduleFade() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .MetalCanvasMIDIActivity)) { noti in
            lastEvent = Date(); count += 1
            if let info = noti.userInfo { push(formatEvent(info)) }
            // Wake on activity and fade after inactivity window
            stopFade(); scheduleFade()
        }
        .overlay(InstrumentBinder(onSet: { name, value in
            switch name {
            case "monitor.fadeSeconds": self.fadeSeconds = Double(value); self.scheduleFade()
            case "monitor.opacity.min": self.minOpacity = Double(value); self.scheduleFade()
            case "monitor.maxLines": self.maxLines = max(1, Int(value)); self.trim()
            default: break
            }
        }))
    }
}

// Binds a MetalInstrument (MIDI 2.0) to this overlay and maps PE setUniform to overlay properties.
fileprivate struct InstrumentBinder: NSViewRepresentable {
    let onSet: (String, Float) -> Void
    final class Sink: MetalSceneRenderer { var onSet: ((String, Float)->Void)?; func setUniform(_ name: String, float: Float) { onSet?(name, float) }
        func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
        func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
        func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    }
    final class Coordinator { var instrument: MetalInstrument? = nil }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        let sink = Sink(); sink.onSet = onSet
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "GridDevMonitor", instanceId: "griddev-monitor", displayName: "MIDI Monitor Overlay")
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.enable()
        context.coordinator.instrument = inst
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.instrument?.disable(); coordinator.instrument = nil }
}
