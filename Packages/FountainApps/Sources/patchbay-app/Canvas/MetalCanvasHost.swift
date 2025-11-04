import SwiftUI
import AppKit
import MetalViewKit

struct MetalCanvasHost: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    var body: some View {
        ZStack(alignment: .topLeading) {
            UMPRecorderBinder()
            MetalCanvasView(zoom: vm.zoom,
                            translation: vm.translation,
                            gridMinor: CGFloat(vm.grid),
                            majorEvery: vm.majorEvery,
                            nodes: {
                // Map Stage nodes for now; other kinds can be added later
                var nodes: [MetalCanvasNode] = []
                for n in vm.nodes {
                    if let dash = state.dashboard[n.id], dash.kind == .stageA4 {
                        let rect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
                        let page = dash.props["page"] ?? "A4"
                        // Prefer individual margin keys if present; otherwise parse aggregated string
                        let mTop = Double(dash.props["margins.top"] ?? "")
                        let mLeft = Double(dash.props["margins.left"] ?? "")
                        let mBottom = Double(dash.props["margins.bottom"] ?? "")
                        let mRight = Double(dash.props["margins.right"] ?? "")
                        let margins: MVKMargins = {
                            if let t = mTop, let l = mLeft, let b = mBottom, let r = mRight {
                                return MVKMargins(top: t, leading: l, bottom: b, trailing: r)
                            }
                            let parts = (dash.props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap{ Double($0.trimmingCharacters(in: .whitespaces)) }
                            if parts.count == 4 { return MVKMargins(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[3]) }
                            return MVKMargins(top: 18, leading: 18, bottom: 18, trailing: 18)
                        }()
                        let bl = CGFloat(Double(dash.props["baseline"] ?? "12") ?? 12)
                        nodes.append(StageMetalNode(id: n.id, frameDoc: rect, title: dash.props["title"] ?? (n.title ?? n.id), page: page, margins: margins, baseline: bl))
                    }
                    else if let dash = state.dashboard[n.id], dash.kind == .replayPlayer {
                        let rect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
                        let title = dash.props["title"] ?? (n.title ?? n.id)
                        let fps = Float(dash.props["fps"] ?? "10") ?? 10
                        let playing = (dash.props["playing"] ?? "0") == "1"
                        let frame = Int(dash.props["frame"] ?? "0") ?? 0
                        nodes.append(ReplayMetalNode(id: n.id, frameDoc: rect, title: title, fps: fps, playing: playing, frameIndex: frame))
                    }
                    else {
                        // Generic fallback node so story patches render even without dashboard entries
                        let rect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
                        let ins = canonicalSortPorts(n.ports).filter{ $0.dir == .input }.map{ $0.id }
                        let outs = canonicalSortPorts(n.ports).filter{ $0.dir == .output }.map{ $0.id }
                        nodes.append(GenericMetalNode(id: n.id, frameDoc: rect, inPorts: ins, outPorts: outs))
                    }
                }
                return nodes
            }, edges: {
                // Map VM edges to MetalCanvasEdge by splitting refs like "A.out"
                var out: [MetalCanvasEdge] = []
                for e in vm.edges {
                    let fp = e.from.split(separator: ".", maxSplits: 1).map(String.init)
                    let tp = e.to.split(separator: ".", maxSplits: 1).map(String.init)
                    if fp.count == 2, tp.count == 2 {
                        out.append(MetalCanvasEdge(fromNode: fp[0], fromPort: fp[1], toNode: tp[0], toPort: tp[1]))
                    }
                }
                return out
            },
                            selected: { vm.selected },
                            onSelect: { sel in vm.selected = sel; vm.selection = sel.first },
                            onMoveBy: { ids, delta in
                                guard delta != .zero else { return }
                                for i in 0..<vm.nodes.count {
                                    if ids.contains(vm.nodes[i].id) {
                                        vm.nodes[i].x += Int(delta.width)
                                        vm.nodes[i].y += Int(delta.height)
                                    }
                                }
                            },
                            onTransformChanged: { t, z in vm.translation = t; vm.zoom = z },
                            instrument: MetalInstrumentDescriptor(manufacturer: "Fountain", product: "PatchBayCanvas", instanceId: "main", displayName: "PatchBay Canvas"))
            // Right-edge hover hit area for MIDI monitor
            MidiMonitorHitArea()
            // Marquee removed: selection is command-click/toggle only
            // Cursor instrument: expose pointer position as a MIDI 2.0 instrument
            CursorInstrumentBinder()
            // Grid instrument: control spacing and majors via MIDI 2.0
            GridInstrumentBinder()
            // Right Pane (Viewport) instrument: expose view/doc edges for grid alignment tests
            ViewportInstrumentBinder()
            // Per-Stage MIDI 2.0 instruments: expose PE for page/margins/baseline
            StageInstrumentsBinder()
            // Per-Replay MIDI 2.0 instruments: expose PE for play/fps/frame
            ReplayInstrumentsBinder()
            // Selection + interaction handled inside MetalCanvasView (no zoom HUD; use MIDI monitor)
            // MIDI 2.0 Monitor overlay (top-right, fades when idle; jumps to full on hover)
            Midi2MonitorOverlay(isHot: MidiMonitorHitArea.hotBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 8)
            // Human‑readable node titles rendered as SwiftUI overlays (so generic nodes are meaningful)
            NodeTitlesOverlay()
            // Add-Instruments context menu removed in baseline; no right-click UI
        }
    }
}

// SwiftUI overlay that draws node titles in view space using VM transform (zoom + translation)
fileprivate struct NodeTitlesOverlay: View {
    @EnvironmentObject var vm: EditorVM
    @State private var lastPass: Bool? = nil
    private func viewPoint(doc: CGPoint, in size: CGSize) -> CGPoint {
        let z = max(0.0001, vm.zoom)
        let x = (doc.x + vm.translation.x) * z
        let y = (doc.y + vm.translation.y) * z
        return CGPoint(x: x, y: y)
    }
    var body: some View {
        GeometryReader { geo in
            ForEach(vm.nodes, id: \.id) { n in
                let title = (n.title ?? n.id)
                // Position label slightly above the node's top-left
                let pt = viewPoint(doc: CGPoint(x: CGFloat(n.x), y: CGFloat(n.y) - 18), in: geo.size)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.8)).cornerRadius(4)
                    .position(x: pt.x, y: pt.y)
                // PASS/FAIL badge for "present" node
                if n.id.lowercased() == "present", let pass = lastPass {
                    let badge = pass ? "PASS" : "FAIL"
                    let color = pass ? Color.green.opacity(0.85) : Color.red.opacity(0.85)
                    let bpt = viewPoint(doc: CGPoint(x: CGFloat(n.x + n.w) + 10, y: CGFloat(n.y) - 10), in: geo.size)
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color).cornerRadius(4)
                        .position(x: bpt.x, y: bpt.y)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            NotificationCenter.default.addObserver(forName: Notification.Name("PBVRTResult"), object: nil, queue: .main) { noti in
                if let p = noti.userInfo?["pass"] as? Bool {
                    DispatchQueue.main.async { lastPass = p }
                }
            }
        }
    }
}

// A shared hover detector so the monitor overlay can pause its fade when the right edge is touched.
fileprivate struct MidiMonitorHitArea: View {
    @State private var hovering = false
    static private var _hot: Bool = false
    static var hotBinding: Binding<Bool> {
        Binding(get: { _hot }, set: { _ in })
    }
    var body: some View {
        Color.clear
            .frame(maxHeight: .infinity)
            .frame(width: 56)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                Self._hot = inside
            }
    }
}

// Bind one MetalInstrument per Stage node, mapping PE setUniform → AppState dashboard props.
fileprivate final class MarqueeSink: MetalSceneRenderer {
    private var origin = CGPoint.zero
    private var current = CGPoint.zero
    private var selectionMode: Int = 0
    private var active = false

    func setUniform(_ name: String, float: Float) {
        switch name {
        case "marquee.origin.doc.x":
            origin.x = CGFloat(float)
        case "marquee.origin.doc.y":
            origin.y = CGFloat(float)
        case "marquee.current.doc.x":
            current.x = CGFloat(float)
        case "marquee.current.doc.y":
            current.y = CGFloat(float)
        case "marquee.selection.mode":
            selectionMode = Int(float.rounded())
        case "marquee.command":
            let command = Int(float.rounded())
            switch command {
            case 0:
                active = false
                post(op: "cancel")
            case 1:
                active = true
                post(op: "begin")
            case 2:
                guard active else { return }
                post(op: "update")
            case 3:
                guard active else { return }
                post(op: "end")
                active = false
            default:
                break
            }
        default:
            break
        }
    }

    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}

    func stateSnapshot() -> [String: Any] {
        [
            "marquee.active": active ? 1.0 : 0.0,
            "marquee.origin.doc.x": Double(origin.x),
            "marquee.origin.doc.y": Double(origin.y),
            "marquee.current.doc.x": Double(current.x),
            "marquee.current.doc.y": Double(current.y),
            "marquee.selection.mode": Double(selectionMode)
        ]
    }

    private func post(op: String) {
        NotificationCenter.default.post(name: .MetalCanvasMarqueeCommand, object: nil, userInfo: [
            "op": op,
            "origin.doc.x": Double(origin.x),
            "origin.doc.y": Double(origin.y),
            "current.doc.x": Double(current.x),
            "current.doc.y": Double(current.y),
            "selectionMode": selectionMode
        ])
    }
}

fileprivate struct MarqueeInstrumentBinder: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if context.coordinator.instrument == nil {
            let sink = MarqueeSink()
            let descriptor = MetalInstrumentDescriptor(
                manufacturer: "Fountain",
                product: "Marquee",
                instanceId: "marquee",
                displayName: "Marquee Tool"
            )
            let instrument = MetalInstrument(sink: sink, descriptor: descriptor)
            instrument.stateProvider = { sink.stateSnapshot() }
            instrument.enable()
            context.coordinator.instrument = instrument
            context.coordinator.sink = sink
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.instrument?.disable()
        coordinator.instrument = nil
        coordinator.sink = nil
    }
    final class Coordinator {
        var instrument: MetalInstrument?
        var sink: MarqueeSink?
    }
}

// MARK: - Cursor Instrument (view/doc position + visibility)
fileprivate final class CursorSink: MetalSceneRenderer {
    // Latest cursor positions
    private(set) var viewPoint: CGPoint = .zero
    private(set) var docPoint: CGPoint = .zero
    private(set) var visible: Bool = true
    // Converters provided by the binder (thread-safe snapshots)
    var viewToDoc: ((CGPoint) -> CGPoint)?
    var docToView: ((CGPoint) -> CGPoint)?

    func setUniform(_ name: String, float: Float) {
        switch name {
        case "cursor.visible":
            visible = (float >= 0.5)
        case "cursor.view.x":
            viewPoint.x = CGFloat(float)
            if let toDoc = viewToDoc { docPoint = toDoc(viewPoint) }
            postActivity()
        case "cursor.view.y":
            viewPoint.y = CGFloat(float)
            if let toDoc = viewToDoc { docPoint = toDoc(viewPoint) }
            postActivity()
        case "cursor.doc.x":
            docPoint.x = CGFloat(float)
            if let toView = docToView { viewPoint = toView(docPoint) }
            postActivity()
        case "cursor.doc.y":
            docPoint.y = CGFloat(float)
            if let toView = docToView { viewPoint = toView(docPoint) }
            postActivity()
        default:
            break
        }
    }
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    func stateSnapshot() -> [String: Any] {
        [
            "cursor.visible": visible ? 1.0 : 0.0,
            "cursor.view.x": Double(viewPoint.x),
            "cursor.view.y": Double(viewPoint.y),
            "cursor.doc.x": Double(docPoint.x),
            "cursor.doc.y": Double(docPoint.y)
        ]
    }
    private func postActivity() {
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "ui.cursor.move",
            "view.x": Double(viewPoint.x),
            "view.y": Double(viewPoint.y),
            "doc.x": Double(docPoint.x),
            "doc.y": Double(docPoint.y),
            "visible": visible ? 1 : 0
        ])
    }
}

fileprivate struct CursorInstrumentBinder: NSViewRepresentable {
    @EnvironmentObject var vm: EditorVM
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = CursorTrackingView()
        v.coordinator = context.coordinator
        if context.coordinator.instrument == nil {
            let sink = CursorSink()
            context.coordinator.sink = sink
            let desc = MetalInstrumentDescriptor(
                manufacturer: "Fountain",
                product: "Cursor",
                instanceId: "cursor",
                displayName: "PatchBay Cursor"
            )
            let inst = MetalInstrument(sink: sink, descriptor: desc)
            inst.stateProvider = { sink.stateSnapshot() }
            inst.enable()
            context.coordinator.instrument = inst
        }
        // Install tracking
        v.setupTracking()
        // Seed converters
        updateConverters(coordinator: context.coordinator)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        updateConverters(coordinator: context.coordinator)
    }
    private func updateConverters(coordinator: Coordinator) {
        guard let sink = coordinator.sink else { return }
        let s = max(0.0001, vm.zoom)
        let t = vm.translation
        sink.viewToDoc = { p in CGPoint(x: (p.x / s) - t.x, y: (p.y / s) - t.y) }
        sink.docToView = { d in CGPoint(x: (d.x + t.x) * s, y: (d.y + t.y) * s) }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.instrument?.disable()
        coordinator.instrument = nil
        coordinator.sink = nil
    }
    final class Coordinator {
        var instrument: MetalInstrument?
        var sink: CursorSink?
        @MainActor fileprivate func handleMouseMoved(in view: NSView, event: NSEvent) {
            guard let sink else { return }
            let p = view.convert(event.locationInWindow, from: nil)
            sink.setUniform("cursor.view.x", float: Float(p.x))
            sink.setUniform("cursor.view.y", float: Float(p.y))
        }
        @MainActor fileprivate func handleEntered() { sink?.setUniform("cursor.visible", float: 1) }
        @MainActor fileprivate func handleExited() { sink?.setUniform("cursor.visible", float: 0) }
    }
    final class CursorTrackingView: NSView {
        weak var coordinator: Coordinator?
        private var area: NSTrackingArea?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            setupTracking()
        }
        func setupTracking() {
            if let a = area { removeTrackingArea(a) }
            let opts: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited]
            let a = NSTrackingArea(rect: self.bounds, options: opts, owner: self, userInfo: nil)
            addTrackingArea(a)
            area = a
        }
        override func mouseMoved(with event: NSEvent) {
            coordinator?.handleMouseMoved(in: self, event: event)
        }
        override func mouseEntered(with event: NSEvent) { coordinator?.handleEntered() }
        override func mouseExited(with event: NSEvent) { coordinator?.handleExited() }
    }
}

// MARK: - Grid Instrument (minor spacing + majorEvery)
fileprivate final class GridSink: MetalSceneRenderer {
    var onSet: ((String, Float) -> Void)?
    func setUniform(_ name: String, float: Float) { onSet?(name, float) }
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    var snapshot: (() -> [String: Any])? = nil
}

fileprivate struct GridInstrumentBinder: NSViewRepresentable {
    @EnvironmentObject var vm: EditorVM
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if context.coordinator.instrument == nil {
            let sink = GridSink()
            sink.onSet = { [weak vm] name, value in
                guard let vm else { return }
                Task { @MainActor in
                    switch name {
                    case "grid.minor": vm.grid = max(1, Int(value.rounded()))
                    case "grid.majorEvery": vm.majorEvery = max(1, Int(value.rounded()))
                    default: break
                    }
                }
            }
            sink.snapshot = { [weak vm] in
                guard let vm else { return [:] }
                return [
                    "grid.minor": Double(vm.grid),
                    "grid.majorEvery": vm.majorEvery,
                    "zoom": Double(vm.zoom),
                    "translation.x": Double(vm.translation.x),
                    "translation.y": Double(vm.translation.y)
                ]
            }
            let desc = MetalInstrumentDescriptor(
                manufacturer: "Fountain",
                product: "Grid",
                instanceId: "grid",
                displayName: "Grid"
            )
            let inst = MetalInstrument(sink: sink, descriptor: desc)
            inst.stateProvider = { sink.snapshot?() ?? [:] }
            inst.enable()
            context.coordinator.instrument = inst
            context.coordinator.sink = sink
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.instrument?.disable()
        coordinator.instrument = nil
        coordinator.sink = nil
    }
    final class Coordinator {
        var instrument: MetalInstrument?
        var sink: GridSink?
    }
}

// MARK: - Viewport Instrument (right pane)
fileprivate final class ViewportSink: MetalSceneRenderer {
    var snapshot: (() -> [String: Any])? = nil
    func setUniform(_ name: String, float: Float) {}
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
}

fileprivate struct ViewportInstrumentBinder: NSViewRepresentable {
    @EnvironmentObject var vm: EditorVM
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        if context.coordinator.instrument == nil {
            let sink = ViewportSink()
            sink.snapshot = { [weak vm] in
                guard let vm else { return [:] }
                let zoom = max(0.0001, vm.zoom)
                let tx = vm.translation.x
                let ty = vm.translation.y
                // With grid anchored to viewport left, contact point sits at x=0 regardless of translation.
                let g = max(1, vm.grid)
                let contactX: CGFloat = 0
                // Derive right contact info and visible columns from current window width when available
                let W: CGFloat = NSApp.keyWindow?.contentView?.bounds.width ?? 0
                let step = CGFloat(g) * zoom
                let rightIndex = step > 0 ? Int(floor(W / step)) : 0
                let rightX = CGFloat(rightIndex) * step
                let visibleCols = rightIndex + 1 // include left contact at 0
                return [
                    "viewport.zoom": Double(zoom),
                    "viewport.tx": Double(tx),
                    "viewport.ty": Double(ty),
                    "grid.minor": Double(vm.grid),
                    "contact.grid.left.view.x": Double(contactX),
                    "viewport.width": Double(W),
                    "grid.step": Double(step),
                    "contact.grid.right.index": rightIndex,
                    "contact.grid.right.view.x": Double(rightX),
                    "visible.grid.columns": visibleCols
                ]
            }
            let desc = MetalInstrumentDescriptor(
                manufacturer: "Fountain",
                product: "Viewport",
                instanceId: "viewport",
                displayName: "Right Pane"
            )
            let inst = MetalInstrument(sink: sink, descriptor: desc)
            inst.stateProvider = { sink.snapshot?() ?? [:] }
            inst.enable()
            context.coordinator.instrument = inst
            context.coordinator.sink = sink
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.instrument?.disable()
        coordinator.instrument = nil
        coordinator.sink = nil
    }
    final class Coordinator {
        var instrument: MetalInstrument?
        var sink: ViewportSink?
    }
}

fileprivate struct StageInstrumentsBinder: NSViewRepresentable {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    final class StageSink: MetalSceneRenderer { var onSet: ((String, Float, String)->Void)?
        let stageId: String
        init(stageId: String) { self.stageId = stageId }
        func setUniform(_ name: String, float: Float) { onSet?(name, float, stageId) }
        func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
        func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
        func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    }
    final class Coordinator {
        var instruments: [String: MetalInstrument] = [:] // stageId → instrument
        var sinks: [String: StageSink] = [:]
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Compute current stage ids
        let stageIds = vm.nodes.compactMap { n in state.dashboard[n.id]?.kind == .stageA4 ? n.id : nil }
        // Remove instruments for deleted stages
        for (sid, inst) in context.coordinator.instruments where !stageIds.contains(sid) {
            inst.disable()
            context.coordinator.instruments.removeValue(forKey: sid)
            context.coordinator.sinks.removeValue(forKey: sid)
        }
        // Ensure instruments for current stages
        for sid in stageIds {
            if context.coordinator.instruments[sid] == nil {
                let sink = StageSink(stageId: sid)
                sink.onSet = { name, value, stageId in
                    Task { @MainActor in
                        guard let node = state.dashboard[stageId], node.kind == .stageA4 else { return }
                        var p = node.props
                        func set(_ k: String, _ v: Double) { p[k] = String(format: "%.3f", v) }
                        switch name {
                        case "stage.baseline": set("baseline", Double(value))
                        case "stage.margins.top": set("margins.top", Double(value))
                        case "stage.margins.left": set("margins.left", Double(value))
                        case "stage.margins.bottom": set("margins.bottom", Double(value))
                        case "stage.margins.right": set("margins.right", Double(value))
                        case "stage.page": p["page"] = (Int(value.rounded()) == 1) ? "Letter" : "A4"
                        default: break
                        }
                        state.updateDashProps(id: stageId, props: p)
                        if let i = vm.nodeIndex(by: stageId) {
                            func baselineCount(_ props: [String:String]) -> Int {
                                let page = props["page"]?.lowercased() ?? "a4"
                                let height: Double = (page == "letter") ? 792.0 : 842.0
                                let baseline = Double(props["baseline"] ?? "12") ?? 12.0
                                let mparts = (props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                                let top = mparts.count == 4 ? mparts[0] : (Double(props["margins.top"] ?? "18") ?? 18)
                                let bottom = mparts.count == 4 ? mparts[2] : (Double(props["margins.bottom"] ?? "18") ?? 18)
                                let usable = max(0.0, height - top - bottom)
                                return max(1, Int(floor(usable / max(1.0, baseline))))
                            }
                            func pageSize(_ props: [String:String]) -> (Int,Int) {
                                let page = props["page"]?.lowercased() ?? "a4"
                                return page == "letter" ? (612, 792) : (595, 842)
                            }
                            let newCount = baselineCount(p)
                            var ports: [PBPort] = []
                            for k in 0..<newCount { ports.append(.init(id: "in\(k)", side: .left, dir: .input, type: "view")) }
                            vm.nodes[i].ports = canonicalSortPorts(ports)
                            let sz = pageSize(p); vm.nodes[i].w = sz.0; vm.nodes[i].h = sz.1
                        }
                    }
                }
                let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "Stage", instanceId: "stage-\(sid)", displayName: "Stage #\(sid)")
                let inst = MetalInstrument(sink: sink, descriptor: desc)
                // Report current state via PE GET
                inst.stateProvider = { [weak state] in
                    guard let dash = state?.dashboard[sid], dash.kind == .stageA4 else { return [:] }
                    var mTop = 18.0, mLeft = 18.0, mBottom = 18.0, mRight = 18.0
                    if let s = dash.props["margins"], !s.isEmpty {
                        let parts = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                        if parts.count == 4 { mTop = parts[0]; mLeft = parts[1]; mBottom = parts[2]; mRight = parts[3] }
                    } else {
                        // Also support individual keys if present
                        mTop = Double(dash.props["margins.top"] ?? "18") ?? 18
                        mLeft = Double(dash.props["margins.left"] ?? "18") ?? 18
                        mBottom = Double(dash.props["margins.bottom"] ?? "18") ?? 18
                        mRight = Double(dash.props["margins.right"] ?? "18") ?? 18
                    }
                    let baseline = Double(dash.props["baseline"] ?? "12") ?? 12
                    let page = (dash.props["page"] ?? "A4").lowercased() == "letter" ? 1.0 : 0.0
                    return [
                        "stage.baseline": baseline,
                        "stage.margins.top": mTop,
                        "stage.margins.left": mLeft,
                        "stage.margins.bottom": mBottom,
                        "stage.margins.right": mRight,
                        "stage.page": page
                    ]
                }
                inst.enable()
                context.coordinator.instruments[sid] = inst
                context.coordinator.sinks[sid] = sink
            }
        }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        for (_, inst) in coordinator.instruments { inst.disable() }
        coordinator.instruments.removeAll()
        coordinator.sinks.removeAll()
    }
}
// Overlay to support selection, marquee selection, and drag-moving nodes on the Metal canvas.
fileprivate struct NodeInteractionOverlay: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    @State private var pressStart: CGPoint? = nil
    @State private var marqueeRect: CGRect? = nil
    @State private var pressStartDoc: CGPoint? = nil
    @State private var marqueeSelectionMode: Int = 0
    @State private var draggingIds: Set<String> = []
    @State private var initialPositions: [String:(x:Int,y:Int)] = [:]
    @State private var lastPoint: CGPoint? = nil
    private func transform() -> CanvasTransform { CanvasTransform(scale: vm.zoom, translation: vm.translation) }
    private func nodeViewRect(_ n: PBNode) -> CGRect {
        let t = transform()
        let origin = t.docToView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
        return CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w) * vm.zoom, height: CGFloat(n.h) * vm.zoom)
    }
    private func viewToDoc(_ p: CGPoint) -> CGPoint { transform().viewToDoc(p) }
    private func hitTestNode(at p: CGPoint) -> PBNode? {
        for n in vm.nodes.reversed() { if nodeViewRect(n).contains(p) { return n } }
        return nil
    }
    private func beginDrag(for ids: Set<String>, at start: CGPoint) {
        draggingIds = ids
        initialPositions = [:]
        for id in ids { if let n = vm.node(by: id) { initialPositions[id] = (n.x, n.y) } }
        pressStart = start
        pressStartDoc = viewToDoc(start)
        lastPoint = start
        // Emit drag.start with anchor point in doc-space
        let doc = viewToDoc(start)
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "drag.start",
            "ids": Array(ids),
            "anchor.doc.x": Double(doc.x),
            "anchor.doc.y": Double(doc.y)
        ])
    }
    private func applyDrag(to current: CGPoint) {
        guard let start = pressStart else { return }
        let dxView = current.x - start.x
        let dyView = current.y - start.y
        let s = max(0.0001, vm.zoom)
        let dxDoc = dxView / s
        let dyDoc = dyView / s
        // Snap delta to grid
        let g = max(1, vm.grid)
        let snapDX = CGFloat(g) * (dxDoc / CGFloat(g)).rounded()
        let snapDY = CGFloat(g) * (dyDoc / CGFloat(g)).rounded()
        for (id, pos) in initialPositions {
            if let i = vm.nodeIndex(by: id) {
                vm.nodes[i].x = pos.x + Int(snapDX)
                vm.nodes[i].y = pos.y + Int(snapDY)
            }
        }
        lastPoint = current
    }
    private func postActivity(type: String, _ extra: [String: Any] = [:]) {
        var payload: [String: Any] = ["type": type]
        extra.forEach { payload[$0.key] = $0.value }
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: payload)
    }
    private func handleMarqueeNotification(_ note: Notification) {
        guard let op = note.userInfo?["op"] as? String else { return }
        if let ox = note.userInfo?["origin.doc.x"] as? Double,
           let oy = note.userInfo?["origin.doc.y"] as? Double {
            pressStartDoc = CGPoint(x: ox, y: oy)
        }
        let selectionModeValue: Int
        if let mode = note.userInfo?["selectionMode"] as? Int {
            selectionModeValue = mode
        } else if let modeDouble = note.userInfo?["selectionMode"] as? Double {
            selectionModeValue = Int(modeDouble.rounded())
        } else {
            selectionModeValue = 0
        }
        switch op {
        case "begin":
            guard let startDoc = pressStartDoc else { return }
            marqueeSelectionMode = selectionModeValue
            let startView = transform().docToView(startDoc)
            pressStart = startView
            marqueeRect = CGRect(origin: startView, size: .zero)
            draggingIds.removeAll()
            initialPositions.removeAll()
            lastPoint = nil
            postActivity(type: "marquee.start", [
                "view.x": Double(startView.x),
                "view.y": Double(startView.y),
                "doc.x": Double(startDoc.x),
                "doc.y": Double(startDoc.y)
            ])
        case "update":
            guard
                let startDoc = pressStartDoc,
                let cx = note.userInfo?["current.doc.x"] as? Double,
                let cy = note.userInfo?["current.doc.y"] as? Double
            else { return }
            updateMarqueeFromDoc(start: startDoc, current: CGPoint(x: cx, y: cy))
        case "end":
            guard
                let startDoc = pressStartDoc,
                let cx = note.userInfo?["current.doc.x"] as? Double,
                let cy = note.userInfo?["current.doc.y"] as? Double
            else {
                resetMarqueeState()
                return
            }
            completeMarqueeSelection(startDoc: startDoc, currentDoc: CGPoint(x: cx, y: cy), mode: selectionModeValue)
        case "cancel":
            resetMarqueeState()
        default:
            break
        }
    }
    private func updateMarqueeFromDoc(start: CGPoint, current: CGPoint) {
        let startView = transform().docToView(start)
        let currentView = transform().docToView(current)
        let rect = CGRect(
            x: min(startView.x, currentView.x),
            y: min(startView.y, currentView.y),
            width: abs(currentView.x - startView.x),
            height: abs(currentView.y - startView.y)
        )
        marqueeRect = rect
        postActivity(type: "marquee.update", [
            "min.doc.x": Double(min(start.x, current.x)),
            "min.doc.y": Double(min(start.y, current.y)),
            "max.doc.x": Double(max(start.x, current.x)),
            "max.doc.y": Double(max(start.y, current.y))
        ])
    }
    private func completeMarqueeSelection(startDoc: CGPoint, currentDoc: CGPoint, mode: Int) {
        let rectDoc = CGRect(
            x: min(startDoc.x, currentDoc.x),
            y: min(startDoc.y, currentDoc.y),
            width: abs(currentDoc.x - startDoc.x),
            height: abs(currentDoc.y - startDoc.y)
        )
        applyMarqueeSelection(docRect: rectDoc, selectionMode: mode)
        resetMarqueeState()
    }
    private func applyMarqueeSelection(docRect: CGRect, selectionMode mode: Int) {
        var sel: Set<String> = []
        for n in vm.nodes {
            let nodeRect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
            if nodeRect.intersects(docRect) {
                sel.insert(n.id)
            }
        }
        var newSelection = vm.selected
        switch mode {
        case 1: // additive
            newSelection = newSelection.union(sel)
        case 2: // toggle
            for id in sel {
                if newSelection.contains(id) {
                    newSelection.remove(id)
                } else {
                    newSelection.insert(id)
                }
            }
        default:
            newSelection = sel
        }
        vm.selected = newSelection
        vm.selection = newSelection.first
        postActivity(type: "marquee.end", [
            "min.doc.x": Double(docRect.minX),
            "min.doc.y": Double(docRect.minY),
            "max.doc.x": Double(docRect.maxX),
            "max.doc.y": Double(docRect.maxY),
            "selected": Array(newSelection)
        ])
    }
    private func resetMarqueeState() {
        marqueeRect = nil
        pressStart = nil
        pressStartDoc = nil
        marqueeSelectionMode = 0
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Marquee rectangle visualization
                if let rect = marqueeRect {
                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4,3]))
                        .background(Rectangle().fill(Color.accentColor.opacity(0.08)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                Color.clear
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = v.location
                    if pressStart == nil {
                        // Mouse down
                        pressStart = p
                        let flags = NSApp.currentEvent?.modifierFlags ?? []
                        let isCmd = flags.contains(.command)
                        let isShift = flags.contains(.shift)
                        let docP = viewToDoc(p)
                        pressStartDoc = docP
                        postActivity(type: "ui.pointer.down", [
                            "view.x": Double(p.x), "view.y": Double(p.y),
                            "doc.x": Double(docP.x), "doc.y": Double(docP.y),
                            "mods": (isCmd && isShift ? "cmd+shift" : (isCmd ? "cmd" : (isShift ? "shift" : "")))
                        ])
                        if let hit = hitTestNode(at: p) {
                            var newSel = vm.selected
                            if isCmd {
                                if newSel.contains(hit.id) { newSel.remove(hit.id) } else { newSel.insert(hit.id) }
                            } else if isShift {
                                newSel.insert(hit.id)
                            } else {
                                newSel = [hit.id]
                            }
                            let before = Array(vm.selected)
                            vm.selected = newSel
                            vm.selection = newSel.first
                            postActivity(type: "selection.change", ["before": before, "after": Array(newSel)])
                            if !newSel.isEmpty { beginDrag(for: newSel, at: p) }
                        } else {
                            // Begin marquee selection
                            marqueeRect = CGRect(origin: p, size: .zero)
                            postActivity(type: "marquee.start", [
                                "view.x": Double(p.x), "view.y": Double(p.y),
                                "doc.x": Double(docP.x), "doc.y": Double(docP.y)
                            ])
                        }
                    } else {
                        // Update either drag or marquee
                        if !draggingIds.isEmpty {
                            applyDrag(to: p)
                            if let start = pressStart {
                                let s = max(0.0001, vm.zoom)
                                let dxDoc = (p.x - start.x) / s
                                let dyDoc = (p.y - start.y) / s
                                let g = max(1, vm.grid)
                                let snapDX = CGFloat(g) * (dxDoc / CGFloat(g)).rounded()
                                let snapDY = CGFloat(g) * (dyDoc / CGFloat(g)).rounded()
                                postActivity(type: "drag.move", [
                                    "ids": Array(draggingIds),
                                    "dx.doc": Double(dxDoc), "dy.doc": Double(dyDoc),
                                    "dx.snap": Double(snapDX), "dy.snap": Double(snapDY),
                                    "grid": vm.grid
                                ])
                            }
                        } else if var rect = marqueeRect, let start = pressStart {
                            let x0 = min(start.x, p.x), y0 = min(start.y, p.y)
                            rect.origin = CGPoint(x: x0, y: y0)
                            rect.size = CGSize(width: abs(p.x - start.x), height: abs(p.y - start.y))
                            marqueeRect = rect
                            let a = viewToDoc(CGPoint(x: rect.minX, y: rect.minY))
                            let b = viewToDoc(CGPoint(x: rect.maxX, y: rect.maxY))
                            postActivity(type: "marquee.update", [
                                "min.doc.x": Double(a.x), "min.doc.y": Double(a.y),
                                "max.doc.x": Double(b.x), "max.doc.y": Double(b.y)
                            ])
                        }
                    }
                }
                .onEnded { v in
                    let p = v.location
                    defer {
                        pressStart = nil; pressStartDoc = nil; marqueeRect = nil; draggingIds.removeAll(); initialPositions.removeAll(); lastPoint = nil
                    }
                    if !draggingIds.isEmpty {
                        // Drag finished — selection stays; emit end event
                        if let start = pressStart {
                            let s = max(0.0001, vm.zoom)
                            let dxDoc = (p.x - start.x) / s
                            let dyDoc = (p.y - start.y) / s
                            postActivity(type: "drag.end", [
                                "ids": Array(initialPositions.keys),
                                "dx.doc": Double(dxDoc), "dy.doc": Double(dyDoc)
                            ])
                        }
                        return
                    }
                    // End of marquee or click
                    if let rect = marqueeRect {
                        let flags = NSApp.currentEvent?.modifierFlags ?? []
                        let isCmd = flags.contains(.command)
                        let isShift = flags.contains(.shift)
                        var sel: Set<String> = []
                        for n in vm.nodes { if nodeViewRect(n).intersects(rect) { sel.insert(n.id) } }
                        if isCmd {
                            var toggled = vm.selected
                            for id in sel { if toggled.contains(id) { toggled.remove(id) } else { toggled.insert(id) } }
                            vm.selected = toggled
                        } else if isShift {
                            vm.selected = vm.selected.union(sel)
                        } else {
                            vm.selected = sel
                        }
                        vm.selection = sel.first
                        let a = viewToDoc(CGPoint(x: rect.minX, y: rect.minY))
                        let b = viewToDoc(CGPoint(x: rect.maxX, y: rect.maxY))
                        postActivity(type: "marquee.end", [
                            "min.doc.x": Double(a.x), "min.doc.y": Double(a.y),
                            "max.doc.x": Double(b.x), "max.doc.y": Double(b.y),
                            "selected": Array(vm.selected)
                        ])
                    } else {
                        // Click without drag: set selection to topmost hit or clear
                        if let hit = hitTestNode(at: p) { vm.selected = [hit.id]; vm.selection = hit.id } else { vm.selected.removeAll(); vm.selection = nil }
                        postActivity(type: "selection.set", ["selected": Array(vm.selected)])
                    }
                    let docP = viewToDoc(p)
                    postActivity(type: "ui.pointer.up", ["view.x": Double(p.x), "view.y": Double(p.y), "doc.x": Double(docP.x), "doc.y": Double(docP.y)])
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .MetalCanvasMarqueeCommand)) { note in
            handleMarqueeNotification(note)
        }
    }
}
// Draw selection outlines for selected nodes and a dashed group bounding box.
fileprivate struct SelectionOverlay: View {
    @EnvironmentObject var vm: EditorVM
    private func transform(_ size: CGSize) -> CanvasTransform { CanvasTransform(scale: vm.zoom, translation: vm.translation) }
    private func nodeViewRect(_ n: PBNode, xf: CanvasTransform) -> CGRect {
        let origin = xf.docToView(CGPoint(x: CGFloat(n.x), y: CGFloat(n.y)))
        return CGRect(x: origin.x, y: origin.y, width: CGFloat(n.w) * vm.zoom, height: CGFloat(n.h) * vm.zoom)
    }
    var body: some View {
        GeometryReader { geo in
            let xf = transform(geo.size)
            // Compute selected rects in view space
            let rects: [CGRect] = vm.nodes.filter { vm.selected.contains($0.id) }.map { nodeViewRect($0, xf: xf) }
            // Compute union rect if group selection
            let groupRect: CGRect? = {
                guard rects.count > 1 else { return nil }
                var minX = CGFloat.greatestFiniteMagnitude
                var minY = CGFloat.greatestFiniteMagnitude
                var maxX = CGFloat.leastNormalMagnitude
                var maxY = CGFloat.leastNormalMagnitude
                for r in rects { minX = min(minX, r.minX); minY = min(minY, r.minY); maxX = max(maxX, r.maxX); maxY = max(maxY, r.maxY) }
                return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
            }()
            ZStack(alignment: .topLeading) {
                // Per-node selection boxes
                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .accentColor.opacity(0.15), radius: 3, x: 0, y: 0)
                }
                if let gr = groupRect {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6,4]))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: gr.width, height: gr.height)
                        .position(x: gr.midX, y: gr.midY)
                }
            }
        }
    }
}

import MetalKit
final class ReplayMetalNode: MetalCanvasNode {
    let id: String
    var frameDoc: CGRect
    var title: String
    var fps: Float
    var playing: Bool
    var frameIndex: Int
    init(id: String, frameDoc: CGRect, title: String, fps: Float, playing: Bool, frameIndex: Int) {
        self.id = id; self.frameDoc = frameDoc; self.title = title; self.fps = fps; self.playing = playing; self.frameIndex = frameIndex
    }
    func portLayout() -> [MetalNodePort] { return [] }
    func encode(into view: MTKView, device: MTLDevice, encoder: MTLRenderCommandEncoder, transform: MetalCanvasTransform) {
        let tl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.minY)
        let tr = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.minY)
        let bl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.maxY)
        let br = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.maxY)
        let bgVerts = [tl, bl, tr, tr, bl, br]
        encoder.setVertexBytes(bgVerts, length: bgVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var bg = SIMD4<Float>(0.98, 0.98, 0.985, 1)
        encoder.setFragmentBytes(&bg, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        let border = [tl, tr, tr, br, br, bl, bl, tl]
        encoder.setVertexBytes(border, length: border.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var c = SIMD4<Float>(0.72, 0.74, 0.78, 1)
        encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: border.count)
        // Play indicator
        let inset: CGFloat = 8
        let a = transform.docToNDC(x: frameDoc.minX + inset, y: frameDoc.minY + inset)
        let b = transform.docToNDC(x: frameDoc.minX + inset, y: frameDoc.minY + inset + 14)
        let d = transform.docToNDC(x: frameDoc.minX + inset + 12, y: frameDoc.minY + inset + 7)
        let tri = [a, b, d]
        encoder.setVertexBytes(tri, length: tri.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var triColor = playing ? SIMD4<Float>(0.20,0.65,0.35,1) : SIMD4<Float>(0.75,0.75,0.78,1)
        encoder.setFragmentBytes(&triColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

fileprivate struct ReplayInstrumentsBinder: NSViewRepresentable {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    final class Sink: MetalSceneRenderer {
        let nodeId: String
        weak var state: AppState?
        init(nodeId: String, state: AppState?) { self.nodeId = nodeId; self.state = state }
        func setUniform(_ name: String, float: Float) {
            // Avoid capturing task-isolated self inside a MainActor task; capture values first.
            let nodeId = self.nodeId
            weak var weakState = self.state
            Task { @MainActor in
                guard let state = weakState, let dash = state.dashboard[nodeId], dash.kind == .replayPlayer else { return }
                var p = dash.props
                switch name {
                case "replay.play": p["playing"] = (float > 0.5) ? "1" : "0"
                case "replay.fps": p["fps"] = String(format: "%.3f", Double(float))
                case "replay.frame": p["frame"] = String(Int(float.rounded()))
                default: break
                }
                state.updateDashProps(id: nodeId, props: p)
            }
        }
        func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
        func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
        func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    }
    final class Coordinator { var instruments: [String: MetalInstrument] = [:] }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {
        let ids = vm.nodes.compactMap { n in state.dashboard[n.id]?.kind == .replayPlayer ? n.id : nil }
        for (sid, inst) in context.coordinator.instruments where !ids.contains(sid) { inst.disable(); context.coordinator.instruments.removeValue(forKey: sid) }
        for sid in ids where context.coordinator.instruments[sid] == nil {
            let sink = Sink(nodeId: sid, state: state)
            let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "ReplayPlayer", instanceId: "rp-\(sid)", displayName: "Replay #\(sid)")
            let inst = MetalInstrument(sink: sink, descriptor: desc)
            inst.stateProvider = { [weak state] in
                guard let dash = state?.dashboard[sid], dash.kind == .replayPlayer else { return [:] }
                return [
                    "replay.play": ((dash.props["playing"] ?? "0") == "1") ? 1.0 : 0.0,
                    "replay.fps": Double(dash.props["fps"] ?? "10") ?? 10.0,
                    "replay.frame": Double(dash.props["frame"] ?? "0") ?? 0.0,
                    "replay.length": 0.0
                ]
            }
            inst.enable()
            context.coordinator.instruments[sid] = inst
        }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        for (_, i) in coordinator.instruments { i.disable() }
        coordinator.instruments.removeAll()
    }
}
