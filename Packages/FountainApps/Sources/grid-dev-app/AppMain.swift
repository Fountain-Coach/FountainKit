import SwiftUI
import MetalViewKit
import LauncherSignature
import FountainStoreClient

@main
struct GridDevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("Grid Dev") {
            GridDevView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        Task.detached {
            // Seed & print prompt on boot (policy)
            let prompt = await GridDevApp.buildTeatroPrompt()
            await PromptSeeder.seedAndPrint(appId: "grid-dev", prompt: prompt, facts: [
                "instruments": [[
                    "manufacturer": "Fountain",
                    "product": "GridDev",
                    "instanceId": "grid-dev-1",
                    "displayName": "Grid Dev"
                ],[
                    "manufacturer": "Fountain",
                    "product": "Cursor",
                    "instanceId": "grid-cursor",
                    "displayName": "Grid Cursor"
                ]]
            ])
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class GridVM: ObservableObject {
    @Published var zoom: CGFloat = 1.0
    @Published var translation: CGPoint = .zero
    @Published var grid: Int = 24
    @Published var majorEvery: Int = 5
}

struct GridDevView: View {
    @StateObject private var vm = GridVM()
    @State private var resetOpacity: Double = 0.18
    @State private var resetMinOpacity: Double = 0.18
    @State private var resetFadeSeconds: Double = 3.0
    @State private var resetFadeWork: DispatchWorkItem? = nil
    private func bumpResetAndScheduleFade() {
        withAnimation(.easeOut(duration: 0.12)) { resetOpacity = 1.0 }
        resetFadeWork?.cancel()
        let w = DispatchWorkItem { withAnimation(.linear(duration: resetFadeSeconds)) { resetOpacity = resetMinOpacity } }
        resetFadeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + resetFadeSeconds, execute: w)
    }
    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            MetalCanvasView(
                zoom: vm.zoom,
                translation: vm.translation,
                gridMinor: CGFloat(vm.grid),
                majorEvery: vm.majorEvery,
                nodes: { [] },
                edges: { [] },
                selected: { [] },
                onSelect: { _ in },
                onMoveBy: { _,_ in },
                onTransformChanged: { t, z in vm.translation = t; vm.zoom = z },
                instrument: MetalInstrumentDescriptor(
                    manufacturer: "Fountain",
                    product: "GridDev",
                    instanceId: "grid-dev-1",
                    displayName: "Grid Dev"
                )
            )
            .ignoresSafeArea()
            // UX instrument binder (no visible UI): tune reset fade/opacity via PE
            .overlay(GridDevUXBinder(onSet: { name, value in
                switch name {
                case "reset.opacity.min":
                    resetMinOpacity = Double(value)
                    // if target below new min, snap to min
                    if resetOpacity < resetMinOpacity { resetOpacity = resetMinOpacity }
                    bumpResetAndScheduleFade()
                case "reset.fadeSeconds":
                    resetFadeSeconds = Double(value)
                    bumpResetAndScheduleFade()
                case "reset.opacity.now":
                    withAnimation(.easeOut(duration: 0.12)) { resetOpacity = Double(value) }
                case "reset.bump":
                    bumpResetAndScheduleFade()
                default:
                    break
                }
            }).allowsHitTesting(false))
        }
        // Overlays
        content
            // MIDI monitor pinned to top-right (non-interactive)
            .overlay(alignment: .topTrailing) {
                GridDevMidiMonitorOverlay(isHot: .constant(true))
                    .padding(8)
                    .allowsHitTesting(false)
            }
            // Reset grid button (top-left)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        NotificationCenter.default.post(
                            name: Notification.Name("MetalCanvasRendererCommand"),
                            object: nil,
                            userInfo: ["op": "set", "zoom": 1.0, "tx": 0.0, "ty": 0.0]
                        )
                        // Emit MIDI activity so the monitor reflects the reset immediately
                        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                            "type": "ui.zoom", "zoom": 1.0
                        ])
                        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                            "type": "ui.pan", "x": 0.0, "y": 0.0
                        ])
                        bumpResetAndScheduleFade()
                    } label: {
                        Text("Reset Grid").font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .onHover { hovering in if hovering { withAnimation(.easeOut(duration: 0.12)) { resetOpacity = 1.0 } } else { bumpResetAndScheduleFade() } }
                }
                .opacity(resetOpacity)
                .onReceive(NotificationCenter.default.publisher(for: .MetalCanvasMIDIActivity)) { _ in bumpResetAndScheduleFade() }
                .padding(.leading, 6)
                .padding(.top, 6)
            }
        .frame(minWidth: 800, minHeight: 600)
    }
}

extension GridDevApp {
    @MainActor static func buildTeatroPrompt() -> String {
        return """
        Scene: GridDevApp (Grid‑Only with Persistent Corpus)
        Text:
        - Window: macOS titlebar window, 1440×900pt. Content background white (#FAFBFD).
        - Layout: single full‑bleed canvas; no sidebar, no extra panes, minimal chrome.
        - Only view: “Grid” Instrument filling the content.
          - Grid anchoring: viewport‑anchored. Leftmost vertical line renders at view.x = 0 across all translations/zoom. Topmost horizontal line at view.y = 0.
          - Minor spacing: 24 pt; Major every 5 minors (120 pt). Minor #ECEEF3, Major #D1D6E0. Crisp 1 px.
          - Axes: Doc‑anchored origin lines (x=0/y=0) in faint red (#BF3434) for orientation.
        - MIDI 2.0 Monitor pinned top‑right (non‑interactive); fades out after inactivity; wakes on MIDI activity.
        - Cursor Instrument (always on): crosshair + ring + tiny “0” rendered at the pointer; label offset so it never occludes the zero.
          - Grid coordinates: g: col,row where
            • doc = (view/zoom) − translation
            • leftDoc = 0/zoom − tx, topDoc = 0/zoom − ty
            • col = round((doc.x − leftDoc)/step), row = round((doc.y − topDoc)/step)
            • step = grid.minor
        """
    }
}

// MIDI 2.0 binder for GridDev UX knobs (reset fade/opacity)
fileprivate struct GridDevUXBinder: NSViewRepresentable {
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
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "GridDevUX", instanceId: "griddev-ux", displayName: "Grid Dev UX")
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.enable()
        context.coordinator.instrument = inst
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.instrument?.disable(); coordinator.instrument = nil }
}
