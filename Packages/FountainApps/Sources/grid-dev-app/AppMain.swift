import SwiftUI
import UniformTypeIdentifiers
import MetalViewKit
import LauncherSignature
import FountainStoreClient

@main
struct GridDevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        let title = ProcessInfo.processInfo.environment["APP_TITLE"] ?? "Baseline‑PatchBay"
        WindowGroup(title) {
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
        // Console banner for Baseline‑PatchBay (observability)
        let title = env["APP_TITLE"] ?? "Baseline‑PatchBay"
        print("\n=== \(title) ===\nproduct: baseline-patchbay (grid-dev-app)\nmonitor: fades on idle; wakes on MIDI activity (PE: monitor.fadeSeconds, monitor.opacity.min, monitor.opacity.now)\nreset: button fades/wakes (PE: reset.fadeSeconds, reset.opacity.min, reset.opacity.now, reset.bump)\n===\n")
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
            // Show MRTS prompt alongside creation prompt (policy)
            let mrts = await GridDevApp.buildMRTSPrompt()
            print("\n=== MRTS Teatro Prompt (baseline) ===\n\(mrts)\n=== end mrtsprompt ===\n")
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
    @State private var leftFrac: CGFloat = 0.22
    @State private var rightFrac: CGFloat = 0.26
    @State private var leftItems: [String] = (0..<20).map { "Item #\($0)" }
    @State private var rightItems: [String] = (0..<8).map { "Log #\($0)" }
    private func bumpResetAndScheduleFade() {
        withAnimation(.easeOut(duration: 0.12)) { resetOpacity = 1.0 }
        resetFadeWork?.cancel()
        let w = DispatchWorkItem { withAnimation(.linear(duration: resetFadeSeconds)) { resetOpacity = resetMinOpacity } }
        resetFadeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + resetFadeSeconds, execute: w)
    }
    var body: some View {
        GeometryReader { geo in
            let minPane: CGFloat = 160
            let total = max(geo.size.width, minPane * 3 + 12)
            let leftW = max(minPane, min(total - minPane*2, leftFrac * total))
            let rightW = max(minPane, min(total - leftW - minPane - 12, rightFrac * total))
            let centerW = max(minPane, total - leftW - rightW - 12)
            HStack(spacing: 6) {
                // Left scroll pane
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Left Pane").font(.system(size: 12, weight: .semibold))
                        ForEach(leftItems, id: \.self) { id in
                            Text(id)
                                .font(.system(size: 12))
                                .padding(.vertical, 2)
                                .onDrag { beginDrag(for: id, from: "left") }
                        }
                    }.padding(8)
                }
                .onDrop(of: [UTType.plainText], isTargeted: .constant(false)) { providers in
                    acceptDrop(into: "left", providers: providers)
                }
                .frame(width: leftW)
                .background(Color(nsColor: .textBackgroundColor))
                // Left gutter (draggable)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 6)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let new = max(minPane, min(total - minPane*2, leftW + value.translation.width))
                        leftFrac = new / total
                        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                            "type": "ui.layout.changed", "left.frac": Double(leftFrac), "right.frac": Double(rightFrac)
                        ])
                    })
                // Center canvas
                ZStack(alignment: .topLeading) {
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
                            manufacturer: "Fountain", product: "GridDev", instanceId: "grid-dev-1", displayName: "Grid Dev"
                        )
                    )
                    .overlay(GridDevUXBinder(onSet: { name, value in
                        switch name {
                        case "reset.opacity.min":
                            resetMinOpacity = Double(value)
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
                    // Monitor (top-right) + Reset (top-left)
                    GridDevMidiMonitorOverlay(isHot: .constant(true))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                        .allowsHitTesting(false)
                    // Accept text drops into the canvas area (log the event)
                    Color.clear
                        .contentShape(Rectangle())
                        .onDrop(of: [UTType.plainText], isTargeted: .constant(false)) { providers in
                            if let id = loadFirstString(from: providers) {
                                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                                    "type": "ui.dnd.drop", "item.id": id, "target": "center"
                                ])
                                return true
                            }
                            return false
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            NotificationCenter.default.post(
                                name: Notification.Name("MetalCanvasRendererCommand"),
                                object: nil,
                                userInfo: ["op": "set", "zoom": 1.0, "tx": 0.0, "ty": 0.0]
                            )
                            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "ui.zoom", "zoom": 1.0])
                            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type": "ui.pan", "x": 0.0, "y": 0.0])
                            bumpResetAndScheduleFade()
                        } label: {
                            Text("Reset Grid").font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .onHover { hovering in if hovering { withAnimation(.easeOut(duration: 0.12)) { resetOpacity = 1.0 } } else { bumpResetAndScheduleFade() } }
                    }
                    .opacity(resetOpacity)
                    .onReceive(NotificationCenter.default.publisher(for: .MetalCanvasMIDIActivity)) { _ in bumpResetAndScheduleFade() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 6)
                    .padding(.top, 6)
                }
                .frame(width: centerW)
                // Right gutter (draggable)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 6)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let newRight = max(minPane, min(total - leftW - minPane - 12, rightW - value.translation.width))
                        rightFrac = newRight / total
                        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                            "type": "ui.layout.changed", "left.frac": Double(leftFrac), "right.frac": Double(rightFrac)
                        ])
                    })
                // Right scroll pane
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Right Pane").font(.system(size: 12, weight: .semibold))
                        ForEach(rightItems, id: \.self) { id in
                            Text(id)
                                .font(.system(size: 12))
                                .padding(.vertical, 2)
                                .onDrag { beginDrag(for: id, from: "right") }
                        }
                    }.padding(8)
                }
                .onDrop(of: [UTType.plainText], isTargeted: .constant(false)) { providers in
                    acceptDrop(into: "right", providers: providers)
                }
                .frame(width: rightW)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay(GridDevLayoutBinder(onSet: { name, value in
            let v = CGFloat(max(0.05, min(0.9, Double(value))))
            switch name {
            case "layout.left.frac": leftFrac = v
            case "layout.right.frac": rightFrac = v
            default: break
            }
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "ui.layout.changed", "left.frac": Double(leftFrac), "right.frac": Double(rightFrac)
            ])
        }).allowsHitTesting(false))
        .frame(minWidth: 960, minHeight: 640)
    }

    // MARK: - Drag & Drop
    private func beginDrag(for id: String, from source: String) -> NSItemProvider {
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "ui.dnd.begin", "item.id": id, "source": source
        ])
        return NSItemProvider(object: id as NSString)
    }
    private func acceptDrop(into target: String, providers: [NSItemProvider]) -> Bool {
        guard let id = loadFirstString(from: providers) else { return false }
        var moved = false
        if target == "left" {
            if let idx = rightItems.firstIndex(of: id) { rightItems.remove(at: idx); moved = true }
            if !leftItems.contains(id) { leftItems.append(id); moved = true }
        } else if target == "right" {
            if let idx = leftItems.firstIndex(of: id) { leftItems.remove(at: idx); moved = true }
            if !rightItems.contains(id) { rightItems.append(id); moved = true }
        }
        if moved {
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "ui.dnd.drop", "item.id": id, "target": target
            ])
        }
        return moved
    }
    private func loadFirstString(from providers: [NSItemProvider]) -> String? {
        for p in providers {
            let sem = DispatchSemaphore(value: 0)
            var out: String? = nil
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                defer { sem.signal() }
                if let data = item as? Data, let s = String(data: data, encoding: .utf8) { out = s }
                else if let s = item as? String { out = s }
                else if let ns = item as? NSString { out = String(ns) }
            }
            _ = sem.wait(timeout: .now() + 0.5)
            if let s = out { return s }
        }
        return nil
    }
}

extension GridDevApp {
    @MainActor static func buildTeatroPrompt() -> String {
        return """
        Scene: GridDevApp — Three‑Pane Baseline (Canvas Center)
        Text:
        - Window: macOS titlebar window, 1440×900 pt; content background #FAFBFD.
        - Layout: three vertical scroll panes with draggable borders (gutters 6 pt):
          • Left Pane (scrollable): list scaffold. Default width ≈ 22% (min 160 pt).
          • Center Pane: contains the “Grid” canvas instrument (fills center).
          • Right Pane (scrollable): monitor/log scaffold. Default width ≈ 26% (min 160 pt).
          • Gutters draggable horizontally; widths clamp to ≥160 pt; proportions persist during resize.
        - Canvas (center): Baseline grid instrument with viewport‑anchored grid (left contact at view.x=0, top at view.y=0), minor=24 pt, majorEvery=5, axes at doc origin.
        - MIDI overlay: monitor/controls fade after inactivity; wake on MIDI activity.
        - Layout control via MIDI‑CI PE: `layout.left.frac`, `layout.right.frac` (0..1) adjust pane fractions and emit `ui.layout.changed`.
        - Drag & Drop (panes): items can be dragged from Left → Right and back; drops emit `ui.dnd.begin` and `ui.dnd.drop` events. Center accepts drops (logged only).
        """
    }
}

extension GridDevApp {
    static func buildMRTSPrompt() -> String {
        return """
        Scene: Baseline‑PatchBay — Three‑Pane Layout (MRTS)
        Text:
        - Objective: verify three‑pane draggable layout plus baseline canvas invariants and pane drag‑and‑drop.
        - Steps:
          • PE SET `layout.left.frac=0.25` and `layout.right.frac=0.25`; expect `ui.layout.changed`.
          • Simulate window resize (+300 pt width) and assert panes ≥160 pt and center ≥160 pt.
          • Drag left gutter +80 pt right; left fraction increases; event emitted.
          • Drag right gutter +100 pt right; right fraction decreases; event emitted.
          • Drag an item from Left → Right; assert counts (left−1, right+1) and `ui.dnd.*` events.
          • Drag an item from Right → Left; assert counts (right−1, left+1) and `ui.dnd.*` events.
          • Drop an item onto Center; assert `ui.dnd.drop` with target=center.
          • Validate canvas grid contact/spacing and anchor‑stable zoom drift ≤ 1 px.

        Numeric invariants:
        - Pane minimum widths: left/right/center ≥ 160 pt; gutters 6 pt.
        - Fractions clamp [0.05, 0.9]; gutters never cross.
        - Grid contact left at view.x=0; spacing: minor px = grid.minor × zoom; major px = grid.minor × majorEvery × zoom.
        - Monitor emits `ui.zoom(.debug)`/`ui.pan(.debug)`, `ui.layout.changed`, and `ui.dnd.begin/ui.dnd.drop` during DnD.
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

// MIDI 2.0 binder for layout control (pane fractions)
fileprivate struct GridDevLayoutBinder: NSViewRepresentable {
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
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "GridDevLayout", instanceId: "griddev-layout", displayName: "Grid Dev Layout")
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.enable()
        context.coordinator.instrument = inst
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.instrument?.disable(); coordinator.instrument = nil }
}
