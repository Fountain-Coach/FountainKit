import SwiftUI
import AppKit
import MetalViewKit

// Shared holder to expose the bridge instrument to overlays
@MainActor
final class CsoundBridgeHolder: ObservableObject {
    static let shared = CsoundBridgeHolder()
    @Published var instrument: MetalInstrument? = nil
}

// A sink that ignores incoming UMP/PE; used to host a MetalInstrument
fileprivate final class NoopSink: MetalSceneRenderer {
    func setUniform(_ name: String, float: Float) {}
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    func vendorEvent(topic: String, data: Any?) {}
}

/// Attaches a dedicated MetalInstrument named "Csound Bridge" to the view hierarchy.
/// Overlays can use CsoundBridgeHolder.shared.instrument to send CC/notes to external synths.
struct CsoundBridgeInstrumentBinder: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        if context.coordinator.instrument == nil {
            let sink = NoopSink()
            let desc = MetalInstrumentDescriptor(
                manufacturer: "Fountain",
                product: "CsoundBridge",
                instanceId: "csound-bridge",
                displayName: "Csound Bridge"
            )
            let inst = MetalInstrument(sink: sink, descriptor: desc)
            inst.enable()
            context.coordinator.instrument = inst
            CsoundBridgeHolder.shared.instrument = inst
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.instrument?.disable()
        coordinator.instrument = nil
        if CsoundBridgeHolder.shared.instrument === coordinator.instrument {
            CsoundBridgeHolder.shared.instrument = nil
        }
    }
    final class Coordinator { var instrument: MetalInstrument? }
}
