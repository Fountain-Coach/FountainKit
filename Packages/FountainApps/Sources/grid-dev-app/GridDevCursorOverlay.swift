import SwiftUI
import MetalViewKit

struct GridDevCursorOverlay: View {
    @ObservedObject var vm: GridVM
    @State private var viewXY: CGPoint = .zero
    @State private var docXY: CGPoint = .zero
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cursor Instrument")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(String(format: "view: %4.0f, %4.0f", viewXY.x, viewXY.y))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                Text(String(format: "doc: %4.0f, %4.0f", docXY.x, docXY.y))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(Binder(vm: vm, onUpdate: { v, d in
            viewXY = v; docXY = d
        }))
    }
}

fileprivate struct Binder: NSViewRepresentable {
    let vm: GridVM
    let onUpdate: (CGPoint, CGPoint) -> Void
    final class Sink: MetalSceneRenderer {
        var onUpdate: ((CGPoint, CGPoint) -> Void)?
        var viewToDoc: ((CGPoint)->CGPoint)?
        var docToView: ((CGPoint)->CGPoint)?
        private(set) var v: CGPoint = .zero
        private(set) var d: CGPoint = .zero
        func setUniform(_ name: String, float: Float) {
            switch name {
            case "cursor.view.x": v.x = CGFloat(float); if let t = viewToDoc { d = t(v) }; onUpdate?(v,d)
            case "cursor.view.y": v.y = CGFloat(float); if let t = viewToDoc { d = t(v) }; onUpdate?(v,d)
            case "cursor.doc.x": d.x = CGFloat(float); if let t = docToView { v = t(d) }; onUpdate?(v,d)
            case "cursor.doc.y": d.y = CGFloat(float); if let t = docToView { v = t(d) }; onUpdate?(v,d)
            default: break
            }
        }
        func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
        func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
        func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    }
    final class Coordinator {
        var instrument: MetalInstrument? = nil
        var sink: Sink? = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = Tracking()
        v.coordinator = context.coordinator
        let sink = Sink(); sink.onUpdate = onUpdate
        context.coordinator.sink = sink
        let desc = MetalInstrumentDescriptor(
            manufacturer: "Fountain",
            product: "Cursor",
            instanceId: "grid-cursor",
            displayName: "Grid Cursor"
        )
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.enable()
        context.coordinator.instrument = inst
        v.setupTracking()
        updateConverters(context)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { updateConverters(context) }
    private func updateConverters(_ context: Context) {
        guard let sink = context.coordinator.sink else { return }
        let s = max(0.0001, vm.zoom)
        let t = vm.translation
        sink.viewToDoc = { p in CGPoint(x: (p.x / s) - t.x, y: (p.y / s) - t.y) }
        sink.docToView = { d in CGPoint(x: (d.x + t.x) * s, y: (d.y + t.y) * s) }
    }
    static func dismantleNSView(_ nsView: NSView, context: Context) {
        context.coordinator.instrument?.disable()
        context.coordinator.instrument = nil
        context.coordinator.sink = nil
    }
    final class Tracking: NSView {
        weak var coordinator: Coordinator?
        private var area: NSTrackingArea?
        override func updateTrackingAreas() { super.updateTrackingAreas(); setupTracking() }
        func setupTracking() {
            if let a = area { removeTrackingArea(a) }
            let opts: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited]
            let a = NSTrackingArea(rect: self.bounds, options: opts, owner: self, userInfo: nil)
            addTrackingArea(a); area = a
        }
        override func mouseMoved(with event: NSEvent) {
            guard let s = coordinator?.sink else { return }
            let p = convert(event.locationInWindow, from: nil)
            s.setUniform("cursor.view.x", float: Float(p.x))
            s.setUniform("cursor.view.y", float: Float(p.y))
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "ui.cursor.move", "view.x": Double(p.x), "view.y": Double(p.y)
            ])
        }
        override func mouseEntered(with event: NSEvent) {}
        override func mouseExited(with event: NSEvent) {}
    }
}

