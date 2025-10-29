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
                            instrument: MetalInstrumentDescriptor(manufacturer: "Fountain", product: "PatchBayCanvas", instanceId: "main", displayName: "PatchBay Canvas"))
            // Right-edge hover hit area for MIDI monitor
            MidiMonitorHitArea()
            // Per-Stage MIDI 2.0 instruments: expose PE for page/margins/baseline
            StageInstrumentsBinder()
            // Per-Replay MIDI 2.0 instruments: expose PE for play/fps/frame
            ReplayInstrumentsBinder()
            // Selection + interaction now handled inside MetalCanvasView (MTKView subclass)
            // HUD: zoom and origin
            Text(String(format: "Zoom %.2fx  Origin (%.0f, %.0f)", Double(vm.zoom), Double(vm.translation.x), Double(vm.translation.y)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(8)
            // MIDI 2.0 Monitor overlay (top-right, fades when idle; jumps to full on hover)
            Midi2MonitorOverlay(isHot: MidiMonitorHitArea.hotBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 8)
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
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Compute current stage ids
        let stageIds = vm.nodes.compactMap { n in state.dashboard[n.id]?.kind == .stageA4 ? n.id : nil }
        // Remove instruments for deleted stages
        for (sid, inst) in context.coordinator.instruments where !stageIds.contains(sid) { inst.disable(); context.coordinator.instruments.removeValue(forKey: sid) }
        // Ensure instruments for current stages
        for sid in stageIds {
            if context.coordinator.instruments[sid] == nil {
                let sink = StageSink(stageId: sid)
                sink.onSet = { name, value, stageId in
                    guard var node = state.dashboard[stageId], node.kind == .stageA4 else { return }
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
            }
        }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        for (_, inst) in coordinator.instruments { inst.disable() }
        coordinator.instruments.removeAll()
    }
}
// Overlay to support selection, marquee selection, and drag-moving nodes on the Metal canvas.
fileprivate struct NodeInteractionOverlay: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    @State private var pressStart: CGPoint? = nil
    @State private var marqueeRect: CGRect? = nil
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
                        pressStart = nil; marqueeRect = nil; draggingIds.removeAll(); initialPositions.removeAll(); lastPoint = nil
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
        var bgVerts = [tl, bl, tr, tr, bl, br]
        encoder.setVertexBytes(bgVerts, length: bgVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var bg = SIMD4<Float>(0.98, 0.98, 0.985, 1)
        encoder.setFragmentBytes(&bg, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        var border = [tl, tr, tr, br, br, bl, bl, tl]
        encoder.setVertexBytes(border, length: border.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var c = SIMD4<Float>(0.72, 0.74, 0.78, 1)
        encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: border.count)
        // Play indicator
        let inset: CGFloat = 8
        let a = transform.docToNDC(x: frameDoc.minX + inset, y: frameDoc.minY + inset)
        let b = transform.docToNDC(x: frameDoc.minX + inset, y: frameDoc.minY + inset + 14)
        let d = transform.docToNDC(x: frameDoc.minX + inset + 12, y: frameDoc.minY + inset + 7)
        var tri = [a, b, d]
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
