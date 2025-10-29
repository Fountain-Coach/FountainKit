#if canImport(SwiftUI) && canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import SwiftUI
import AppKit
import Metal
import MetalKit
import CoreMIDI

public extension Notification.Name {
    static let MetalCanvasMIDIActivity = Notification.Name("MetalCanvasMIDIActivity")
}

public struct MetalCanvasView: NSViewRepresentable {
    public typealias NodesProvider = () -> [MetalCanvasNode]
    public typealias EdgesProvider = () -> [MetalCanvasEdge]
    private let nodesProvider: NodesProvider
    private let edgesProvider: EdgesProvider
    private let zoom: CGFloat
    private let translation: CGPoint
    private let gridMinor: CGFloat
    private let majorEvery: Int
    private let instrument: MetalInstrumentDescriptor?
    public init(zoom: CGFloat, translation: CGPoint, gridMinor: CGFloat = 24, majorEvery: Int = 5, nodes: @escaping NodesProvider, edges: @escaping EdgesProvider = { [] }, instrument: MetalInstrumentDescriptor? = nil) {
        self.zoom = zoom
        self.translation = translation
        self.gridMinor = gridMinor
        self.majorEvery = max(1, majorEvery)
        self.nodesProvider = nodes
        self.edgesProvider = edges
        self.instrument = instrument
    }
    public func makeNSView(context: Context) -> MTKView {
        let v = MTKView()
        v.device = MTLCreateSystemDefaultDevice()
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColorMake(0.965, 0.965, 0.975, 1.0)
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        if let renderer = MetalCanvasRenderer(mtkView: v) {
            context.coordinator.renderer = renderer
            v.delegate = renderer
            renderer.update(zoom: zoom, translation: translation, gridMinor: gridMinor, majorEvery: majorEvery, nodes: nodesProvider(), edges: edgesProvider())
            if let desc = instrument {
                let sink = CanvasInstrumentSink(renderer: renderer)
                let inst = MetalInstrument(sink: sink, descriptor: desc)
                inst.enable()
                context.coordinator.instrument = inst
            }
        }
        return v
    }
    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.update(zoom: zoom, translation: translation, gridMinor: gridMinor, majorEvery: majorEvery, nodes: nodesProvider(), edges: edgesProvider())
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }
public final class Coordinator { fileprivate var renderer: MetalCanvasRenderer?; fileprivate var instrument: MetalInstrument? }
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
    private var zoom: CGFloat = 1.0
    private var translation: CGPoint = .zero

    init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.view = mtkView
        self.device = device
        self.commandQueue = queue
        super.init()
        do { try buildPipeline(pixelFormat: mtkView.colorPixelFormat) } catch { return nil }
    }
    func update(zoom: CGFloat, translation: CGPoint, gridMinor: CGFloat, majorEvery: Int, nodes: [MetalCanvasNode], edges: [MetalCanvasEdge]) {
        self.zoom = zoom
        self.translation = translation
        self.gridMinor = gridMinor
        self.majorEvery = max(1, majorEvery)
        self.nodes = nodes
        self.edges = edges
    }
    @MainActor
    func applyUniform(_ name: String, value: Float) {
        switch name {
        case "zoom": self.zoom = CGFloat(max(0.25, min(3.0, value)))
        case "translation.x": self.translation.x = CGFloat(value)
        case "translation.y": self.translation.y = CGFloat(value)
        default: break
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        // Use a shared pipeline and transform for all nodes
        enc.setRenderPipelineState(pipeline)
        let xf = MetalCanvasTransform(
            zoom: Float(zoom),
            translation: SIMD2<Float>(Float(translation.x), Float(translation.y)),
            drawableSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        // Grid background
        drawGrid(in: view, encoder: enc, xf: xf)
        // Draw nodes
        for node in nodes { node.encode(into: view, device: device, encoder: enc, transform: xf) }
        // Gather port centers (doc -> NDC)
        var portMap: [String:[String:SIMD2<Float>]] = [:]
        for node in nodes {
            let centers = node.portDocCenters()
            var entry: [String:SIMD2<Float>] = [:]
            for c in centers { entry[c.id] = xf.docToNDC(x: c.doc.x, y: c.doc.y) }
            portMap[node.id] = entry
        }
        // Draw port dots as small quads (~3 px radius)
        let W = max(1.0, Float(view.drawableSize.width))
        let H = max(1.0, Float(view.drawableSize.height))
        let rpx: Float = 3.0
        let dx = 2 * rpx / W
        let dy = 2 * rpx / H
        var portVerts: [SIMD2<Float>] = []
        for (nid, ports) in portMap {
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
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
    private func drawGrid(in view: MTKView, encoder: MTLRenderCommandEncoder, xf: MetalCanvasTransform) {
        let z = max(0.0001, CGFloat(zoom))
        let minDocX = 0 / z - translation.x
        let maxDocX = CGFloat(view.drawableSize.width) / z - translation.x
        let minDocY = 0 / z - translation.y
        let maxDocY = CGFloat(view.drawableSize.height) / z - translation.y
        let step = max(1.0, gridMinor)
        // Vertical lines
        var vMinor: [SIMD2<Float>] = []
        var vMajor: [SIMD2<Float>] = []
        let startVX = floor(minDocX / step)
        let endVX = ceil(maxDocX / step)
        var idx = Int(startVX)
        var x = startVX * step
        while x <= endVX * step {
            let a = xf.docToNDC(x: x, y: minDocY)
            let b = xf.docToNDC(x: x, y: maxDocY)
            if (idx % max(1, majorEvery)) == 0 { vMajor.append(contentsOf: [a,b]) } else { vMinor.append(contentsOf: [a,b]) }
            idx += 1
            x += step
        }
        // Horizontal lines
        var hMinor: [SIMD2<Float>] = []
        var hMajor: [SIMD2<Float>] = []
        let startHY = floor(minDocY / step)
        let endHY = ceil(maxDocY / step)
        var idy = Int(startHY)
        var y = startHY * step
        while y <= endHY * step {
            let a = xf.docToNDC(x: minDocX, y: y)
            let b = xf.docToNDC(x: maxDocX, y: y)
            if (idy % max(1, majorEvery)) == 0 { hMajor.append(contentsOf: [a,b]) } else { hMinor.append(contentsOf: [a,b]) }
            idy += 1
            y += step
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
        // Origin axes (compass)
        let oH = [xf.docToNDC(x: -9999, y: 0), xf.docToNDC(x: 9999, y: 0)]
        let oV = [xf.docToNDC(x: 0, y: -9999), xf.docToNDC(x: 0, y: 9999)]
        let axis = SIMD4<Float>(0.75, 0.20, 0.20, 1)
        draw(oH, rgba: axis); draw(oV, rgba: axis)
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
