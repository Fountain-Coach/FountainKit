import SwiftUI
import AppKit
import FountainStoreClient
import MetalViewKit

@main
struct QuietFrameSonifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("QuietFrame Sonify") {
            QuietFrameView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct QuietFrameView: View {
    @State private var saliency: Double = 0
    @State private var frameRect: CGRect = .zero
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(NSColor.windowBackgroundColor)
                VStack {
                    Spacer()
                    ZStack {
                        QuietFrameShape()
                            .fill(Color.white)
                            .overlay(
                                QuietFrameShape()
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                            .frame(width: 1024, height: 1536)
                            .background(FrameReporter(rect: $frameRect))
                        MouseTracker(onMove: { p in
                            updateSaliency(point: p)
                        })
                        .frame(width: 1024, height: 1536)
                        .allowsHitTesting(true)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .trailing) {
                    HStack(spacing: 10) {
                        Text(String(format: "saliency: %.3f", saliency)).monospaced().font(.caption)
                        ProgressView(value: saliency).frame(width: 140)
                    }
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(10)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(minWidth: 960, minHeight: 720)
    }

    private func updateSaliency(point: CGPoint) {
        guard frameRect.contains(point) else {
            sendCC(value7: 0)
            saliency = 0
            return
        }
        let cx = frameRect.midX, cy = frameRect.midY
        let dx = Double(abs(point.x - cx)) / Double(max(1, frameRect.width) * 0.5)
        let dy = Double(abs(point.y - cy)) / Double(max(1, frameRect.height) * 0.5)
        let d = min(1.0, sqrt(dx*dx + dy*dy))
        let s = max(0, 1.0 - d)
        saliency = s
        let v7 = UInt8(max(0, min(127, Int((s * 127.0).rounded()))))
        sendCC(value7: v7)
        maybeTriggerNote(s)
    }

    private func sendCC(value7: UInt8) {
        guard let inst = QuietFrameInstrument.shared.instrument else { return }
        inst.sendCC(controller: 1, value7: value7)
    }

    private var threshold: Double { 0.65 }
    @State private var lastNote: UInt8 = 0
    @State private var lastTriggered: Bool = false
    private func maybeTriggerNote(_ s: Double) {
        guard let inst = QuietFrameInstrument.shared.instrument else { return }
        let was = lastTriggered
        let now = s >= threshold
        if now && !was {
            let scale: [UInt8] = [60, 62, 65, 67, 69, 72]
            let idx = min(scale.count - 1, max(0, Int((s * Double(scale.count)).rounded())))
            let note = scale[idx]
            let vel: UInt8 = max(20, UInt8((s * 127).rounded()))
            inst.sendNoteOn(note: note, velocity7: vel)
            lastNote = note
        } else if !now && was {
            if lastNote != 0 { inst.sendNoteOff(note: lastNote, velocity7: 0) }
            lastNote = 0
        }
        lastTriggered = now
    }
}

struct QuietFrameShape: Shape {
    func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: 6) }
}

struct FrameReporter: View {
    @Binding var rect: CGRect
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: RectKey.self, value: geo.frame(in: .global))
        }
        .onPreferenceChange(RectKey.self) { rect = $0 }
    }
}

private struct RectKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    nonisolated static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - Mouse tracker (AppKit)
struct MouseTracker: NSViewRepresentable {
    var onMove: (CGPoint) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onMove = onMove
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class TrackingView: NSView {
        var onMove: ((CGPoint) -> Void)?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            let opts: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
            let ta = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
            addTrackingArea(ta)
        }
        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let p = convert(event.locationInWindow, from: nil)
            // Convert to global for consistent frameRect matching
            if let w = window {
                let screenP = w.convertPoint(toScreen: p)
                onMove?(screenP)
            }
        }
    }
}

// Expose a single MIDI 2.0 instrument for the app
@MainActor final class QuietFrameInstrument {
    static let shared = QuietFrameInstrument()
    let instrument: MetalInstrument?
    init() {
        let sink = NoopSink()
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "QuietFrame", instanceId: "qf-1", displayName: "Quiet Frame")
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.enable()
        self.instrument = inst
    }
    private final class NoopSink: MetalSceneRenderer {
        func setUniform(_ name: String, float: Float) {}
        func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
        func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
        func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    }
}
