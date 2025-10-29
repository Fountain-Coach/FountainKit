#if canImport(SwiftUI) && canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import SwiftUI
import AppKit
import Metal
import MetalKit

public struct MetalCanvasView: NSViewRepresentable {
    public typealias NodesProvider = () -> [MetalCanvasNode]
    private let nodesProvider: NodesProvider
    private let zoom: CGFloat
    private let translation: CGPoint
    public init(zoom: CGFloat, translation: CGPoint, nodes: @escaping NodesProvider) {
        self.zoom = zoom
        self.translation = translation
        self.nodesProvider = nodes
    }
    public func makeNSView(context: Context) -> MTKView {
        let v = MTKView()
        v.device = MTLCreateSystemDefaultDevice()
        v.colorPixelFormat = .bgra8Unorm
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        if let renderer = MetalCanvasRenderer(mtkView: v) {
            context.coordinator.renderer = renderer
            v.delegate = renderer
            renderer.update(zoom: zoom, translation: translation, nodes: nodesProvider())
        }
        return v
    }
    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.update(zoom: zoom, translation: translation, nodes: nodesProvider())
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }
public final class Coordinator { fileprivate var renderer: MetalCanvasRenderer? }
}
@MainActor
final class MetalCanvasRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState!
    private var nodes: [MetalCanvasNode] = []
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
    func update(zoom: CGFloat, translation: CGPoint, nodes: [MetalCanvasNode]) {
        self.zoom = zoom
        self.translation = translation
        self.nodes = nodes
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
            translation: SIMD2<Float>(Float(translation.x) * Float(max(0.0001, zoom)), Float(translation.y) * Float(max(0.0001, zoom))),
            drawableSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        for node in nodes {
            node.encode(into: view, device: device, encoder: enc, transform: xf)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
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

#endif
