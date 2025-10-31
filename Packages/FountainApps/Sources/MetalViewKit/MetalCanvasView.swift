#if canImport(SwiftUI) && canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import SwiftUI
import AppKit
import Metal
import MetalKit
import CoreMIDI

public extension Notification.Name {
    static let MetalCanvasMIDIActivity = Notification.Name("MetalCanvasMIDIActivity")
    static let MetalCanvasUMPOut = Notification.Name("MetalCanvasUMPOut")
}

public struct MetalCanvasView: NSViewRepresentable {
    public typealias NodesProvider = () -> [MetalCanvasNode]
    public typealias EdgesProvider = () -> [MetalCanvasEdge]
    public typealias SelectedProvider = () -> Set<String>
    public typealias SelectHandler = (Set<String>) -> Void
    public typealias MoveByHandler = (_ ids: Set<String>, _ deltaDoc: CGSize) -> Void
    public typealias TransformChanged = (_ translation: CGPoint, _ zoom: CGFloat) -> Void
    private let nodesProvider: NodesProvider
    private let edgesProvider: EdgesProvider
    private let zoom: CGFloat
    private let translation: CGPoint
    private let gridMinor: CGFloat
    private let majorEvery: Int
    private let instrument: MetalInstrumentDescriptor?
    private let selectedProvider: SelectedProvider
    private let onSelect: SelectHandler
    private let onMoveBy: MoveByHandler
    private let onTransformChanged: TransformChanged
    public init(zoom: CGFloat,
                translation: CGPoint,
                gridMinor: CGFloat = 24,
                majorEvery: Int = 5,
                nodes: @escaping NodesProvider,
                edges: @escaping EdgesProvider = { [] },
                selected: @escaping SelectedProvider = { [] },
                onSelect: @escaping SelectHandler = { _ in },
                onMoveBy: @escaping MoveByHandler = { _,_  in },
                onTransformChanged: @escaping TransformChanged = { _,_ in },
                instrument: MetalInstrumentDescriptor? = nil) {
        self.zoom = zoom
        self.translation = translation
        self.gridMinor = gridMinor
        self.majorEvery = max(1, majorEvery)
        self.nodesProvider = nodes
        self.edgesProvider = edges
        self.selectedProvider = selected
        self.onSelect = onSelect
        self.onMoveBy = onMoveBy
        self.onTransformChanged = onTransformChanged
        self.instrument = instrument
    }
    public func makeNSView(context: Context) -> MTKView {
        let v = MetalCanvasNSView()
        v.device = MTLCreateSystemDefaultDevice()
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColorMake(0.965, 0.965, 0.975, 1.0)
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        if let renderer = MetalCanvasRenderer(mtkView: v) {
            context.coordinator.renderer = renderer
            v.delegate = renderer
            renderer.update(zoom: zoom, translation: translation, gridMinor: gridMinor, majorEvery: majorEvery, nodes: nodesProvider(), edges: edgesProvider())
            renderer.selectionProvider = selectedProvider
            // Test hook: publish renderer for observers (tests only)
            NotificationCenter.default.post(name: Notification.Name("MetalCanvasRendererReady"), object: nil, userInfo: ["renderer": renderer])
            if let desc = instrument {
                let sink = CanvasInstrumentSink(renderer: renderer)
                let inst = MetalInstrument(sink: sink, descriptor: desc)
                inst.enable()
                context.coordinator.instrument = inst
                // Bridge app activity events into UMP vendor JSON
                NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { noti in
                    var dict: [String: Any] = [:]
                    noti.userInfo?.forEach { k, v in dict[String(describing: k)] = v }
                    inst.sendVendorJSONEvent(topic: dict["type"] as? String ?? "event", dict: dict)
                }
                // Provide state snapshot for PE GET
                inst.stateProvider = { [weak renderer] in
                    guard let r = renderer else { return [:] }
                    return [
                        "zoom": Double(r.currentZoom),
                        "translation.x": Double(r.currentTranslation.x),
                        "translation.y": Double(r.currentTranslation.y),
                        "grid.minor": Double(r.currentGridMinor),
                        "grid.majorEvery": r.currentMajorEvery
                    ]
                }
            } else {
                // Default: midified by default — create per-view instrument automatically
                let sink = CanvasInstrumentSink(renderer: renderer)
                let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "Canvas", displayName: "Canvas")
                let inst = MetalInstrument(sink: sink, descriptor: desc)
                inst.enable()
                context.coordinator.instrument = inst
                NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { noti in
                    var dict: [String: Any] = [:]
                    noti.userInfo?.forEach { k, v in dict[String(describing: k)] = v }
                    inst.sendVendorJSONEvent(topic: dict["type"] as? String ?? "event", dict: dict)
                }
                inst.stateProvider = { [weak renderer] in
                    guard let r = renderer else { return [:] }
                    return [
                        "zoom": Double(r.currentZoom),
                        "translation.x": Double(r.currentTranslation.x),
                        "translation.y": Double(r.currentTranslation.y),
                        "grid.minor": Double(r.currentGridMinor),
                        "grid.majorEvery": r.currentMajorEvery
                    ]
                }
            }
        } else {
            v.isPaused = true
            v.enableSetNeedsDisplay = true
        }
        // Wire interaction callbacks and shared state for hit-testing
        context.coordinator.gridMinor = gridMinor
        context.coordinator.nodesProvider = nodesProvider
        context.coordinator.selectedProvider = selectedProvider
        context.coordinator.onSelect = onSelect
        context.coordinator.onMoveBy = onMoveBy
        context.coordinator.onTransformChanged = onTransformChanged
        if let mv = v as? MetalCanvasNSView { mv.coordinator = context.coordinator }
        return v
    }
    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.update(zoom: zoom, translation: translation, gridMinor: gridMinor, majorEvery: majorEvery, nodes: nodesProvider(), edges: edgesProvider())
        context.coordinator.renderer?.selectionProvider = selectedProvider
        context.coordinator.nodesProvider = nodesProvider
        context.coordinator.selectedProvider = selectedProvider
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }
@MainActor
public final class Coordinator: NSObject {
    fileprivate var renderer: MetalCanvasRenderer?
    fileprivate var instrument: MetalInstrument?
    fileprivate var nodesProvider: NodesProvider = { [] }
    fileprivate var selectedProvider: SelectedProvider = { [] }
    fileprivate var onSelect: SelectHandler = { _ in }
    fileprivate var onMoveBy: MoveByHandler = { _,_ in }
    fileprivate var onTransformChanged: TransformChanged = { _,_ in }
    fileprivate var gridMinor: CGFloat = 24
    // Drag state
    fileprivate var pressView: CGPoint? = nil
    fileprivate var lastDoc: CGPoint? = nil
    fileprivate var draggingIds: Set<String> = []
    fileprivate var marqueeStart: CGPoint? = nil
    private var marqueeStartDoc: CGPoint? = nil
    private var marqueeSelectionMode: Int = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMarqueeNotification(_:)),
                                               name: .MetalCanvasMarqueeCommand,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleMarqueeNotification(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let op = info["op"] as? String
        var originPoint: CGPoint? = nil
        if let ox = info["origin.doc.x"] as? Double, let oy = info["origin.doc.y"] as? Double {
            originPoint = CGPoint(x: ox, y: oy)
        }
        var currentPoint: CGPoint? = nil
        if let cx = info["current.doc.x"] as? Double, let cy = info["current.doc.y"] as? Double {
            currentPoint = CGPoint(x: cx, y: cy)
        }
        var modeOverride: Int? = nil
        if let mode = info["selectionMode"] as? Int {
            modeOverride = mode
        } else if let modeDouble = info["selectionMode"] as? Double {
            modeOverride = Int(modeDouble.rounded())
        }
        handleMarqueeCommand(op: op, origin: originPoint, current: currentPoint, modeOverride: modeOverride)
    }

    @MainActor
    private func handleMarqueeCommand(op: String?, origin: CGPoint?, current: CGPoint?, modeOverride: Int?) {
        guard let renderer else { return }
        guard let op else { return }
        if let origin {
            marqueeStartDoc = origin
        }
        switch op {
        case "begin":
            guard let startDoc = marqueeStartDoc else { return }
            let activeMode = modeOverride ?? 0
            marqueeSelectionMode = activeMode
            renderer.marqueeDocRect = CGRect(origin: startDoc, size: .zero)
            let viewPoint = CGPoint(
                x: (startDoc.x + renderer.currentTranslation.x) * renderer.currentZoom,
                y: (startDoc.y + renderer.currentTranslation.y) * renderer.currentZoom
            )
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "marquee.start",
                "view.x": Double(viewPoint.x),
                "view.y": Double(viewPoint.y),
                "doc.x": Double(startDoc.x),
                "doc.y": Double(startDoc.y),
                "selectionMode": activeMode
            ])
        case "update":
            guard
                let startDoc = marqueeStartDoc,
                let currentDoc = current
            else { return }
            let rect = CGRect(
                x: min(startDoc.x, currentDoc.x),
                y: min(startDoc.y, currentDoc.y),
                width: abs(currentDoc.x - startDoc.x),
                height: abs(currentDoc.y - startDoc.y)
            )
            renderer.marqueeDocRect = rect
            let activeMode = modeOverride ?? marqueeSelectionMode
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "marquee.update",
                "min.doc.x": Double(rect.minX),
                "min.doc.y": Double(rect.minY),
                "max.doc.x": Double(rect.maxX),
                "max.doc.y": Double(rect.maxY),
                "selectionMode": activeMode
            ])
        case "end":
            guard
                let startDoc = marqueeStartDoc,
                let currentDoc = current
            else {
                clearRemoteMarquee()
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type": "marquee.cancel"
                ])
                return
            }
            let activeMode = modeOverride ?? marqueeSelectionMode
            let rect = CGRect(
                x: min(startDoc.x, currentDoc.x),
                y: min(startDoc.y, currentDoc.y),
                width: abs(currentDoc.x - startDoc.x),
                height: abs(currentDoc.y - startDoc.y)
            )
            renderer.marqueeDocRect = nil
            marqueeStartDoc = nil
            let hitIds: Set<String> = Set(renderer.nodesSnapshot.compactMap { node in
                node.frameDoc.intersects(rect) ? node.id : nil
            })
            var newSelection = selectedProvider()
            switch activeMode {
            case 1:
                newSelection.formUnion(hitIds)
            case 2:
                for id in hitIds {
                    if newSelection.contains(id) {
                        newSelection.remove(id)
                    } else {
                        newSelection.insert(id)
                    }
                }
            default:
                newSelection = hitIds
            }
            onSelect(newSelection)
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "marquee.end",
                "min.doc.x": Double(rect.minX),
                "min.doc.y": Double(rect.minY),
                "max.doc.x": Double(rect.maxX),
                "max.doc.y": Double(rect.maxY),
                "selected": Array(newSelection),
                "selectionMode": activeMode
            ])
            marqueeSelectionMode = 0
        case "cancel":
            clearRemoteMarquee()
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type": "marquee.cancel"
            ])
        default:
            break
        }
    }

    @MainActor
    private func clearRemoteMarquee() {
        renderer?.marqueeDocRect = nil
        marqueeStartDoc = nil
        marqueeSelectionMode = 0
    }
}
}
@MainActor
final class MetalCanvasRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState!
    private var nodes: [MetalCanvasNode] = []
    private var edges: [MetalCanvasEdge] = []
    private var gridMinor: CGFloat = 24
    private var majorEvery: Int = 5
    // Align grid to viewport top-left so the leftmost vertical line sits exactly at view.x=0
    private var anchorGridToViewportTopLeft: Bool = true
    private var canvas = Canvas2D()
    // PE overrides
    private var overrideGridMinor: CGFloat? = nil
    private var overrideMajorEvery: Int? = nil
    // Snapshot accessors
    var currentZoom: CGFloat { canvas.zoom }
    var currentTranslation: CGPoint { canvas.translation }
    var currentGridMinor: CGFloat { overrideGridMinor ?? gridMinor }
    var currentMajorEvery: Int { overrideMajorEvery ?? majorEvery }
    // Snapshots for external hit-testing (read-only)
    var nodesSnapshot: [MetalCanvasNode] { nodes }
    // UI selection and marquee (drawn in Metal)
    var selectionProvider: (() -> Set<String>)?
    var marqueeDocRect: CGRect? = nil
    // Contact publishing (to avoid spamming identical events)
    private var lastContactSignature: (w: Int, zMilli: Int, txMilli: Int, tyMilli: Int, stepMilli: Int)? = nil

    init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.view = mtkView
        self.device = device
        self.commandQueue = queue
        super.init()
        do { try buildPipeline(pixelFormat: mtkView.colorPixelFormat) } catch { return nil }
        // Test hook: accept external transform commands
        NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererCommand"), object: nil, queue: .main) { [weak self] noti in
            guard let self else { return }
            let u = noti.userInfo ?? [:]
            guard let op = u["op"] as? String else { return }
            // Extract values outside the Task to avoid task-isolated capture warnings
            let dx = CGFloat((u["dx"] as? Double) ?? 0)
            let dy = CGFloat((u["dy"] as? Double) ?? 0)
            let vx = CGFloat((u["dx"] as? Double) ?? 0)
            let vy = CGFloat((u["dy"] as? Double) ?? 0)
            let ax = CGFloat((u["anchor.x"] as? Double) ?? 0)
            let ay = CGFloat((u["anchor.y"] as? Double) ?? 0)
            let mag = CGFloat((u["magnification"] as? Double) ?? 0)
            let z = (u["zoom"] as? Double)
            let tx = (u["tx"] as? Double)
            let ty = (u["ty"] as? Double)
            Task { @MainActor in
                switch op {
                case "panBy":
                    self.panBy(docDX: dx, docDY: dy)
                case "panByView":
                    let s = max(0.0001, self.currentZoom)
                    self.panBy(docDX: vx / s, docDY: vy / s)
                case "zoomAround":
                    self.zoomAround(anchorView: CGPoint(x: ax, y: ay), magnification: mag)
                case "set":
                    let prevZ = self.canvas.zoom
                    let prevTX = self.canvas.translation.x
                    let prevTY = self.canvas.translation.y
                    if let z = z { self.canvas.zoom = CGFloat(z) }
                    if let tx = tx { self.canvas.translation.x = CGFloat(tx) }
                    if let ty = ty { self.canvas.translation.y = CGFloat(ty) }
                    NotificationCenter.default.post(name: Notification.Name("MetalCanvasTransformChanged"), object: nil, userInfo: [
                        "zoom": self.canvas.zoom, "tx": self.canvas.translation.x, "ty": self.canvas.translation.y, "op": "set"
                    ])
                    // Publish MIDI activity so monitors can reflect programmatic set/reset
                    if abs(self.canvas.zoom - prevZ) > 1e-6 {
                        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                            "type":"ui.zoom.debug", "zoom": Double(self.canvas.zoom)
                        ])
                    }
                    if abs(self.canvas.translation.x - prevTX) > 1e-6 || abs(self.canvas.translation.y - prevTY) > 1e-6 {
                        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                            "type":"ui.pan.debug", "x": Double(self.canvas.translation.x), "y": Double(self.canvas.translation.y)
                        ])
                    }
                default:
                    break
                }
            }
        }
    }
    func update(zoom: CGFloat, translation: CGPoint, gridMinor: CGFloat, majorEvery: Int, nodes: [MetalCanvasNode], edges: [MetalCanvasEdge]) {
        self.canvas.zoom = zoom
        self.canvas.translation = translation
        self.gridMinor = gridMinor
        self.majorEvery = max(1, majorEvery)
        self.nodes = nodes
        self.edges = edges
    }
    @MainActor
    func applyUniform(_ name: String, value: Float) {
        switch name {
        case "zoom": self.canvas.zoom = CGFloat(max(self.canvas.minZoom, min(self.canvas.maxZoom, CGFloat(value))))
        case "translation.x": self.canvas.translation.x = CGFloat(value)
        case "translation.y": self.canvas.translation.y = CGFloat(value)
        case "grid.minor": self.overrideGridMinor = CGFloat(max(1.0, value))
        case "grid.majorEvery": self.overrideMajorEvery = max(1, Int(value.rounded()))
        default: break
        }
    }
    @MainActor func panBy(docDX: CGFloat, docDY: CGFloat) {
        canvas.translation.x += docDX; canvas.translation.y += docDY
        NotificationCenter.default.post(name: Notification.Name("MetalCanvasTransformChanged"), object: nil, userInfo: [
            "zoom": canvas.zoom, "tx": canvas.translation.x, "ty": canvas.translation.y, "op": "panBy", "dx": docDX, "dy": docDY
        ])
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type":"ui.pan.debug","x": Double(canvas.translation.x),"y": Double(canvas.translation.y),"dx.doc": Double(docDX),"dy.doc": Double(docDY)
        ])
    }
    @MainActor func zoomAround(anchorView: CGPoint, magnification: CGFloat) {
        let before = canvas
        canvas.zoomAround(viewAnchor: anchorView, magnification: magnification)
        NotificationCenter.default.post(name: Notification.Name("MetalCanvasTransformChanged"), object: nil, userInfo: [
            "zoom": canvas.zoom, "tx": canvas.translation.x, "ty": canvas.translation.y, "op": "zoomAround",
            "anchor.x": anchorView.x, "anchor.y": anchorView.y, "magnification": magnification,
            "prev.zoom": before.zoom, "prev.tx": before.translation.x, "prev.ty": before.translation.y
        ])
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type":"ui.zoom.debug","zoom": Double(canvas.zoom),"anchor.view.x": Double(anchorView.x),"anchor.view.y": Double(anchorView.y),"magnification": Double(magnification)
        ])
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        // Use a shared pipeline and transform for all nodes
        enc.setRenderPipelineState(pipeline)
        // Use view bounds in points for transform so overlays (SwiftUI points)
        // and Metal rendering share the same coordinate basis.
        let xf = MetalCanvasTransform(
            zoom: Float(canvas.zoom),
            translation: SIMD2<Float>(Float(canvas.translation.x), Float(canvas.translation.y)),
            drawableSize: SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        )
        // Grid background
        drawGrid(in: view, encoder: enc, xf: xf)
        // Draw nodes
        for node in nodes { node.encode(into: view, device: device, encoder: enc, transform: xf) }
        // Draw selection outlines in Metal
        if let sel = selectionProvider?(), !sel.isEmpty {
            var borderVerts: [SIMD2<Float>] = []
            for n in nodes where sel.contains(n.id) {
                let tl = xf.docToNDC(x: n.frameDoc.minX, y: n.frameDoc.minY)
                let tr = xf.docToNDC(x: n.frameDoc.maxX, y: n.frameDoc.minY)
                let bl = xf.docToNDC(x: n.frameDoc.minX, y: n.frameDoc.maxY)
                let br = xf.docToNDC(x: n.frameDoc.maxX, y: n.frameDoc.maxY)
                borderVerts.append(contentsOf: [tl,tr, tr,br, br,bl, bl,tl])
            }
            if !borderVerts.isEmpty {
                enc.setVertexBytes(borderVerts, length: borderVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
                var accent = SIMD4<Float>(0.20, 0.45, 0.95, 1)
                enc.setFragmentBytes(&accent, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
                enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: borderVerts.count)
            }
        }
        // Gather port centers (doc -> NDC)
        var portMap: [String:[String:SIMD2<Float>]] = [:]
        for node in nodes {
            let centers = node.portDocCenters()
            var entry: [String:SIMD2<Float>] = [:]
            for c in centers { entry[c.id] = xf.docToNDC(x: c.doc.x, y: c.doc.y) }
            portMap[node.id] = entry
        }
        // Draw port dots as small quads (~3 px radius)
        let W = max(1.0, Float(view.bounds.width))
        let H = max(1.0, Float(view.bounds.height))
        let rpx: Float = 3.0
        let dx = 2 * rpx / W
        let dy = 2 * rpx / H
        var portVerts: [SIMD2<Float>] = []
        for (_, ports) in portMap {
            for (_, center) in ports {
                let tl = SIMD2<Float>(center.x - dx, center.y + dy)
                let tr = SIMD2<Float>(center.x + dx, center.y + dy)
                let bl = SIMD2<Float>(center.x - dx, center.y - dy)
                let br = SIMD2<Float>(center.x + dx, center.y - dy)
                portVerts.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }
        if !portVerts.isEmpty {
            enc.setVertexBytes(portVerts, length: portVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
            var colorPorts = SIMD4<Float>(0.18,0.36,0.88,1)
            enc.setFragmentBytes(&colorPorts, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: portVerts.count)
        }
        // Draw wires as straight lines between centers
        var wireVerts: [SIMD2<Float>] = []
        for e in edges {
            if let a = portMap[e.fromNode]?[e.fromPort], let b = portMap[e.toNode]?[e.toPort] {
                wireVerts.append(contentsOf: [a, b])
            }
        }
        if !wireVerts.isEmpty {
            enc.setVertexBytes(wireVerts, length: wireVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
            var colorWire = SIMD4<Float>(0.25,0.28,0.32,1)
            enc.setFragmentBytes(&colorWire, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: wireVerts.count)
        }
        // Draw marquee rectangle if present
        if let m = marqueeDocRect {
            var mv: [SIMD2<Float>] = []
            let tl = xf.docToNDC(x: m.minX, y: m.minY)
            let tr = xf.docToNDC(x: m.maxX, y: m.minY)
            let bl = xf.docToNDC(x: m.minX, y: m.maxY)
            let br = xf.docToNDC(x: m.maxX, y: m.maxY)
            mv.append(contentsOf: [tl,tr, tr,br, br,bl, bl,tl])
            enc.setVertexBytes(mv, length: mv.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
            var c = SIMD4<Float>(0.20,0.45,0.95,1)
            enc.setFragmentBytes(&c, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: mv.count)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
    private func drawGrid(in view: MTKView, encoder: MTLRenderCommandEncoder, xf: MetalCanvasTransform) {
        let z = max(0.0001, CGFloat(canvas.zoom))
        let step = max(1.0, overrideGridMinor ?? gridMinor)
        let W = CGFloat(view.bounds.width)
        let H = CGFloat(view.bounds.height)
        // Convert view rect to doc-space bounds
        let minDocX = 0 / z - canvas.translation.x
        let maxDocX = W / z - canvas.translation.x
        let minDocY = 0 / z - canvas.translation.y
        let maxDocY = H / z - canvas.translation.y
        // Buckets
        var vMinor: [SIMD2<Float>] = []
        var vMajor: [SIMD2<Float>] = []
        var hMinor: [SIMD2<Float>] = []
        var hMajor: [SIMD2<Float>] = []
        if anchorGridToViewportTopLeft {
            // Vertical lines at xV = 0, step*z, 2*step*z, ...
            var xV: CGFloat = 0
            // Base doc index for left edge (nearest grid column index)
            let baseIdx = Int(floor(minDocX / step))
            var col = 0
            while xV <= W + 0.5 {
                let docX = xV / z - canvas.translation.x
                let a = xf.docToNDC(x: docX, y: minDocY)
                let b = xf.docToNDC(x: docX, y: maxDocY)
                let idx = baseIdx + col
                if (idx % max(1, overrideMajorEvery ?? majorEvery)) == 0 { vMajor.append(contentsOf: [a,b]) } else { vMinor.append(contentsOf: [a,b]) }
                xV += step * z
                col += 1
            }
            // Horizontal lines at yV = 0, step*z, ...
            var yV: CGFloat = 0
            let baseRow = Int(floor(minDocY / step))
            var row = 0
            while yV <= H + 0.5 {
                let docY = yV / z - canvas.translation.y
                let a = xf.docToNDC(x: minDocX, y: docY)
                let b = xf.docToNDC(x: maxDocX, y: docY)
                let idx = baseRow + row
                if (idx % max(1, overrideMajorEvery ?? majorEvery)) == 0 { hMajor.append(contentsOf: [a,b]) } else { hMinor.append(contentsOf: [a,b]) }
                yV += step * z
                row += 1
            }
        } else {
            // Original doc-anchored grid
            let startVX = floor(minDocX / step)
            let endVX = ceil(maxDocX / step)
            var idx = Int(startVX)
            var x = startVX * step
            while x <= endVX * step {
                let a = xf.docToNDC(x: x, y: minDocY)
                let b = xf.docToNDC(x: x, y: maxDocY)
                if (idx % max(1, overrideMajorEvery ?? majorEvery)) == 0 { vMajor.append(contentsOf: [a,b]) } else { vMinor.append(contentsOf: [a,b]) }
                idx += 1
                x += step
            }
            let startHY = floor(minDocY / step)
            let endHY = ceil(maxDocY / step)
            var idy = Int(startHY)
            var y = startHY * step
            while y <= endHY * step {
                let a = xf.docToNDC(x: minDocX, y: y)
                let b = xf.docToNDC(x: maxDocX, y: y)
                if (idy % max(1, overrideMajorEvery ?? majorEvery)) == 0 { hMajor.append(contentsOf: [a,b]) } else { hMinor.append(contentsOf: [a,b]) }
                idy += 1
                y += step
            }
        }
        func draw(_ verts: [SIMD2<Float>], rgba: SIMD4<Float>) {
            guard !verts.isEmpty else { return }
            encoder.setVertexBytes(verts, length: verts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
            var c = rgba
            encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: verts.count)
        }
        let minor = SIMD4<Float>(0.92, 0.93, 0.95, 1)
        let major = SIMD4<Float>(0.82, 0.84, 0.88, 1)
        draw(vMinor, rgba: minor)
        draw(hMinor, rgba: minor)
        draw(vMajor, rgba: major)
        draw(hMajor, rgba: major)
        // Origin axes (compass) stay doc-anchored
        let oH = [xf.docToNDC(x: -9999, y: 0), xf.docToNDC(x: 9999, y: 0)]
        let oV = [xf.docToNDC(x: 0, y: -9999), xf.docToNDC(x: 0, y: 9999)]
        let axis = SIMD4<Float>(0.75, 0.20, 0.20, 1)
        draw(oH, rgba: axis); draw(oV, rgba: axis)
        // Publish grid contact summary (left pinned, right derived) sparingly
        publishGridContactIfNeeded(viewBounds: view.bounds)
    }
    private func buildPipeline(pixelFormat: MTLPixelFormat) throws {
        let src = Self.shaderSource
        let opts = MTLCompileOptions()
        if #available(macOS 12.0, *) { opts.languageVersion = .version3_0 }
        let lib = try device.makeLibrary(source: src, options: opts)
        let vs = lib.makeFunction(name: "node_vs")!
        let fs = lib.makeFunction(name: "node_ps")!
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }
    // Node-specific drawing happens in node.encode
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VSOut { float4 pos [[position]]; };
    vertex VSOut node_vs(const device float2 *pos [[ buffer(0) ]], unsigned vid [[ vertex_id ]]) {
        VSOut o; o.pos = float4(pos[vid], 0, 1); return o; }
    fragment float4 node_ps(const VSOut in [[stage_in]], constant float4 &color [[ buffer(0) ]]) { return color; }
    """
}

extension MetalCanvasRenderer {
    @MainActor private func publishGridContactIfNeeded(viewBounds: CGRect) {
        let W = max(0.0, viewBounds.width)
        let step = max(0.0001, (overrideGridMinor ?? gridMinor) * canvas.zoom)
        let rightIndex = Int(floor(W / step))
        let sig: (Int, Int, Int, Int, Int) = (
            Int(W.rounded()),
            Int((canvas.zoom * 1000).rounded()),
            Int((canvas.translation.x * 1000).rounded()),
            Int((canvas.translation.y * 1000).rounded()),
            Int((step * 1000).rounded())
        )
        if let last = lastContactSignature, last == sig { return }
        lastContactSignature = sig
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "grid.contact",
            "viewport.width": Double(W),
            "grid.step": Double(step),
            "contact.grid.left.view.x": 0.0,
            "contact.grid.right.index": rightIndex,
            "contact.grid.right.view.x": Double(rightIndex) * Double(step),
            "visible.grid.columns": rightIndex + 1
        ])
    }
}

// MARK: - Interaction (Mouse) — MTKView subclass
final class MetalCanvasNSView: MTKView {
    weak var coordinator: MetalCanvasView.Coordinator?
    // Low-pass smoothing state for trackpad pan
    private var panVX: CGFloat = 0
    private var panVY: CGFloat = 0
    private let panSmoothingAlpha: CGFloat = 0.35
    // Accept user scroll input only when the window is focused (key).
    // Cursor overlay layers and tracking
    private var cursorRoot: CALayer?
    private var crossLayer: CAShapeLayer?
    // No text/circle layers; only crosshair is drawn at the cursor
    private var cursorArea: NSTrackingArea?
    private func viewToDoc(_ p: CGPoint) -> CGPoint {
        guard let r = coordinator?.renderer else { return .zero }
        let s = max(0.0001, r.currentZoom)
        return CGPoint(x: (p.x / s) - r.currentTranslation.x,
                       y: (p.y / s) - r.currentTranslation.y)
    }
    private func topmostHit(at doc: CGPoint) -> String? {
        guard let r = coordinator?.renderer else { return nil }
        for n in r.nodesSnapshot.reversed() { if n.frameDoc.contains(doc) { return n.id } }
        return nil
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = cursorArea { removeTrackingArea(a) }
        let opts: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited]
        let a = NSTrackingArea(rect: self.bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(a)
        cursorArea = a
    }
    private func ensureCursorLayers() {
        wantsLayer = true
        guard let root = layer else { return }
        if cursorRoot == nil {
            let container = CALayer()
            container.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Disable implicit animations on cursor container (position/bounds)
            container.actions = [
                "position": NSNull(),
                "bounds": NSNull(),
                "contents": NSNull(),
                "sublayers": NSNull()
            ]
            root.addSublayer(container)
            cursorRoot = container

            let cross = CAShapeLayer()
            cross.strokeColor = NSColor.systemBlue.cgColor
            cross.fillColor = NSColor.clear.cgColor
            cross.lineWidth = 1.0
            // Disable implicit animations for crosshair layer updates
            cross.actions = [
                "position": NSNull(),
                "bounds": NSNull(),
                "path": NSNull(),
                "lineWidth": NSNull(),
                "strokeColor": NSNull(),
                "fillColor": NSNull()
            ]
            container.addSublayer(cross)
            crossLayer = cross

            // No circle/label layers
        }
    }
    private func updateCursorGraphics(viewPoint p: CGPoint) {
        ensureCursorLayers()
        guard let r = coordinator?.renderer, let container = cursorRoot, let cross = crossLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.position = p
        // Crosshair only
        let L: CGFloat = 6
        let local = CGMutablePath()
        local.move(to: CGPoint(x: -L, y: 0)); local.addLine(to: CGPoint(x: L, y: 0))
        local.move(to: CGPoint(x: 0, y: -L)); local.addLine(to: CGPoint(x: 0, y: L))
        cross.path = local
        CATransaction.commit()
        // Grid coordinates relative to viewport-anchored grid
        let z = max(0.0001, r.currentZoom)
        let leftDoc = (0.0 / z) - r.currentTranslation.x
        let topDoc  = (0.0 / z) - r.currentTranslation.y
        let doc = CGPoint(x: (p.x / z) - r.currentTranslation.x,
                          y: (p.y / z) - r.currentTranslation.y)
        let step = max(1.0, r.currentGridMinor)
        let gx = Int(round((doc.x - leftDoc) / step))
        let gy = Int(round((doc.y - topDoc) / step))
        // Forward to MIDI monitor for display
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type":"ui.cursor.move",
            "view.x": Int(p.x), "view.y": Int(p.y),
            "doc.x": Int(doc.x.rounded()), "doc.y": Int(doc.y.rounded()),
            "grid.x": gx, "grid.y": gy
        ])
    }
    override func mouseDown(with event: NSEvent) {
        guard let c = coordinator else { return }
        let p = convert(event.locationInWindow, from: nil)
        c.pressView = p
        let doc = viewToDoc(p)
        if let id = topmostHit(at: doc) {
            var sel = c.selectedProvider()
            let mods = event.modifierFlags
            if mods.contains(.command) { if sel.contains(id) { sel.remove(id) } else { sel.insert(id) } }
            else if mods.contains(.shift) { sel.insert(id) }
            else { sel = [id] }
            c.onSelect(sel)
            c.draggingIds = sel
            c.lastDoc = doc
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type":"drag.start", "ids": Array(sel), "anchor.doc.x": Double(doc.x), "anchor.doc.y": Double(doc.y)
            ])
        } else {
            // Blank click: clear selection (no marquee)
            c.onSelect([])
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let c = coordinator else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !c.draggingIds.isEmpty {
            if let last = c.lastDoc {
                let cur = viewToDoc(p)
                let dx = cur.x - last.x
                let dy = cur.y - last.y
                // Snap by grid
                let g = max(1.0, c.gridMinor)
                let sdx = CGFloat(g) * (dx / g).rounded()
                let sdy = CGFloat(g) * (dy / g).rounded()
                c.onMoveBy(c.draggingIds, CGSize(width: sdx, height: sdy))
                c.lastDoc = CGPoint(x: last.x + sdx, y: last.y + sdy)
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type":"drag.move", "ids": Array(c.draggingIds), "dx.doc": Double(dx), "dy.doc": Double(dy),
                    "dx.snap": Double(sdx), "dy.snap": Double(sdy), "grid": Int(c.gridMinor)
                ])
            }
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard let c = coordinator else { return }
        let p = convert(event.locationInWindow, from: nil)
        defer { c.pressView = nil; c.draggingIds.removeAll(); c.lastDoc = nil; c.marqueeStart = nil; c.renderer?.marqueeDocRect = nil }
        if !c.draggingIds.isEmpty {
            let doc = viewToDoc(p)
            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                "type":"drag.end", "ids": Array(c.draggingIds), "doc.x": Double(doc.x), "doc.y": Double(doc.y)
            ])
            return
        }
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        updateCursorGraphics(viewPoint: p)
    }
    override func mouseEntered(with event: NSEvent) {
        // Keep cursor visible when entering
        resetCursorRects()
    }
    override func mouseExited(with event: NSEvent) {
        // nothing
    }
    // Trackpad pan (scroll)
    override func scrollWheel(with event: NSEvent) {
        guard let c = coordinator, let r = c.renderer else { return }
        // Focus-aware gating: ignore scrolls until the window is key to prevent initial transform drift
        if let win = self.window, !win.isKeyWindow { return }
        let s = max(0.0001, r.currentZoom)
        let rawX = event.scrollingDeltaX
        let rawY = event.scrollingDeltaY
        // Follow‑finger: convert device deltas to finger deltas using system inversion flag.
        // When natural scrolling is enabled, isDirectionInvertedFromDevice is true and raw deltas follow the finger.
        // When disabled, raw deltas are opposite the finger, so multiply by -1.
        let inv: CGFloat = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        let dxView = rawX * inv
        let dyView = rawY * inv
        // Low‑pass smoothing to tame jitter
        panVX = panVX * (1 - panSmoothingAlpha) + dxView * panSmoothingAlpha
        panVY = panVY * (1 - panSmoothingAlpha) + dyView * panSmoothingAlpha
        let dxDoc = panVX / s
        let dyDoc = panVY / s
        r.panBy(docDX: dxDoc, docDY: dyDoc)
        c.onTransformChanged(r.currentTranslation, r.currentZoom)
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type":"ui.pan",
            "x": Double(r.currentTranslation.x),
            "y": Double(r.currentTranslation.y),
            "dx.doc": Double(dxDoc),
            "dy.doc": Double(dyDoc),
            "dx.raw": Double(rawX),
            "dy.raw": Double(rawY),
            "precise": event.hasPreciseScrollingDeltas
        ])
    }
    // Trackpad pinch to zoom (anchor-stable)
    override func magnify(with event: NSEvent) {
        guard let c = coordinator, let r = c.renderer else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        r.zoomAround(anchorView: anchor, magnification: CGFloat(event.magnification))
        c.onTransformChanged(r.currentTranslation, r.currentZoom)
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type":"ui.zoom",
            "zoom": Double(r.currentZoom),
            "anchor.view.x": Double(anchor.x),
            "anchor.view.y": Double(anchor.y),
            "magnification": Double(event.magnification)
        ])
    }
}

// Instrument sink adapter for canvas
final class CanvasInstrumentSink: MetalSceneRenderer {
    weak var renderer: MetalCanvasRenderer?
    init(renderer: MetalCanvasRenderer?) { self.renderer = renderer }
    func setUniform(_ name: String, float: Float) {
        guard let r = renderer else { return }
        Task { @MainActor in r.applyUniform(name, value: float) }
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "pe.set", "name": name, "value": float
        ])
    }
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "noteOn", "group": Int(group), "channel": Int(channel), "note": Int(note), "velocity": Int(velocity)
        ])
    }
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "cc", "group": Int(group), "channel": Int(channel), "controller": Int(controller), "value": Int(value)
        ])
    }
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "pb", "group": Int(group), "channel": Int(channel), "value14": Int(value14)
        ])
    }
}

#endif
