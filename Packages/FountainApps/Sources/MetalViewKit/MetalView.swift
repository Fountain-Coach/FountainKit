// Minimal embeddable Metal view for macOS apps (SwiftUI/AppKit)
// Renders the same unlit triangle as SDLKit’s demo via inline Metal shaders.

#if canImport(SwiftUI) && canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import SwiftUI
import AppKit
import Metal
import MetalKit

// Additional controls for scenes rendered by MetalViewKit. The core instrument sink protocol
// (MetalSceneRenderer) lives in MetalInstrument.swift and covers musical events.
public protocol MetalSceneUniformControls: AnyObject {
    func setUniform(_ name: String, float: Float)
}

public typealias MetalSceneOnReady = (MetalSceneRenderer & MetalSceneUniformControls) -> Void

public struct MetalTriangleView: NSViewRepresentable {
    private let onReady: MetalSceneOnReady?
    #if canImport(CoreMIDI)
    private let instrument: MetalInstrumentDescriptor?
    public init(onReady: MetalSceneOnReady? = nil, instrument: MetalInstrumentDescriptor? = nil) {
        self.onReady = onReady
        self.instrument = instrument
    }
    #else
    public init(onReady: MetalSceneOnReady? = nil) { self.onReady = onReady }
    #endif

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        let device = view.device ?? MTLCreateSystemDefaultDevice()
        let pixelFormat = view.colorPixelFormat
        let renderer = MetalTriangleRenderer(device: device, colorPixelFormat: pixelFormat)
        context.coordinator.renderer = renderer
        view.delegate = renderer
        if let r = renderer { onReady?(r) }
        #if canImport(CoreMIDI)
        if let r = renderer, let instrument = instrument {
            let inst = MetalInstrument(sink: r, descriptor: instrument)
            inst.enable()
            context.coordinator.instrument = inst
        }
        #endif
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        // Nothing dynamic to update for now.
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        fileprivate var renderer: MetalTriangleRenderer?
        #if canImport(CoreMIDI)
        fileprivate var instrument: MetalInstrument?
        #endif
    }
}

final class MetalTriangleRenderer: NSObject, MTKViewDelegate, MetalSceneRenderer, MetalSceneUniformControls {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    private var tint: SIMD3<Float> = .init(repeating: 1)
    private var zoom: Float = 1.0
    private var brightness: Float = 0.0
    private var exposure: Float = 0.0
    private var contrast: Float = 1.0
    private var hue: Float = 0.0
    private var saturation: Float = 1.0
    private var blurStrength: Float = 0.0 // no-op for triangle; kept for parity

    init?(device: MTLDevice?, colorPixelFormat: MTLPixelFormat) {
        guard let device = device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
        do {
            try buildPipeline(pixelFormat: colorPixelFormat)
            buildGeometry()
            buildUniforms()
        } catch {
            print("[MetalViewKit] Failed to initialize renderer: \(error)")
            return nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No-op; we render in NDC.
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        // Update uniforms
        let w = max(1.0, Float(view.drawableSize.width))
        let h = max(1.0, Float(view.drawableSize.height))
        var u = Uniforms(
            aspect: h / w,
            zoom: zoom,
            brightness: brightness,
            exposure: exposure,
            contrast: contrast,
            hue: hue,
            saturation: saturation,
            blurStrength: blurStrength,
            pad0: 0,
            tint: tint,
            pad1: 0
        )
        memcpy(uniformBuffer.contents(), &u, MemoryLayout<Uniforms>.size)

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildPipeline(pixelFormat: MTLPixelFormat) throws {
        let src = Self.inlineMetalSource
        let options = MTLCompileOptions()
        if #available(macOS 12.0, *) { options.languageVersion = .version3_0 }
        let library = try device.makeLibrary(source: src, options: options)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "unlit_triangle_vs")
        desc.fragmentFunction = library.makeFunction(name: "unlit_triangle_ps")
        desc.colorAttachments[0].pixelFormat = pixelFormat
        pipelineState = try device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildGeometry() {
        struct Vertex { var position: SIMD3<Float>; var color: SIMD3<Float> }
        let vertices: [Vertex] = [
            .init(position: [-0.6, -0.5, 0.0], color: [1, 0, 0]),
            .init(position: [ 0.0,  0.6, 0.0], color: [0, 1, 0]),
            .init(position: [ 0.6, -0.5, 0.0], color: [0, 0, 1])
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Vertex>.stride,
                                         options: .storageModeShared)
        vertexBuffer.label = "MetalViewKit.TriangleVertices"
    }

    private func buildUniforms() {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)
        uniformBuffer.label = "MetalViewKit.TriangleUniforms"
    }

    struct Uniforms {
        var aspect: Float; var zoom: Float; var brightness: Float; var exposure: Float; var contrast: Float; var hue: Float; var saturation: Float; var blurStrength: Float; var pad0: Float; var tint: SIMD3<Float>; var pad1: Float
    }

    // Minimal inline shaders to mirror SDLKit’s unlit triangle pipeline
    private static let inlineMetalSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VSIn {
        float3 position [[attribute(0)]];
        float3 color    [[attribute(1)]];
    };
    struct VSOut {
        float4 position [[position]];
        float3 color;
    };
    struct Uniforms { float aspect; float zoom; float brightness; float exposure; float contrast; float hue; float saturation; float blurStrength; float pad0; float3 tint; float pad1; };

    static float3 apply_saturation(float3 c, float s) {
        const float3 luma = float3(0.2126, 0.7152, 0.0722);
        float g = dot(c, luma);
        return mix(float3(g, g, g), c, s);
    }
    static float3 apply_contrast(float3 c, float k) {
        return (c - 0.5) * k + 0.5;
    }
    static float3 apply_exposure(float3 c, float e) {
        float f = pow(2.0, e);
        return c * f;
    }
    static float3 apply_brightness(float3 c, float b) {
        return c + float3(b, b, b);
    }
    static float3 rgb_to_yiq(float3 c) {
        float Y = 0.299*c.r + 0.587*c.g + 0.114*c.b;
        float I = 0.596*c.r - 0.274*c.g - 0.322*c.b;
        float Q = 0.211*c.r - 0.523*c.g + 0.312*c.b;
        return float3(Y, I, Q);
    }
    static float3 yiq_to_rgb(float3 y)
    {
        float r = y.x + 0.956*y.y + 0.621*y.z;
        float g = y.x - 0.272*y.y - 0.647*y.z;
        float b = y.x - 1.106*y.y + 1.703*y.z;
        return float3(r,g,b);
    }
    static float3 apply_hue(float3 c, float angle) {
        float3 y = rgb_to_yiq(c);
        float ca = cos(angle), sa = sin(angle);
        float I = y.y * ca - y.z * sa;
        float Q = y.y * sa + y.z * ca;
        return yiq_to_rgb(float3(y.x, I, Q));
    }

    vertex VSOut unlit_triangle_vs(uint vid [[vertex_id]],
                                   const device VSIn *inVerts [[buffer(0)]],
                                   constant Uniforms &u [[buffer(1)]]) {
        VSOut out;
        VSIn v = inVerts[vid];
        float x = v.position.x * u.aspect * u.zoom;
        float y = v.position.y * u.zoom;
        out.position = float4(x, y, v.position.z, 1.0);
        out.color = v.color;
        return out;
    }

    fragment float4 unlit_triangle_ps(VSOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        float3 rgb = in.color * u.tint;
        rgb = apply_brightness(rgb, u.brightness);
        rgb = apply_exposure(rgb, u.exposure);
        rgb = apply_contrast(rgb, u.contrast);
        rgb = apply_saturation(rgb, u.saturation);
        rgb = apply_hue(rgb, u.hue);
        return float4(clamp(rgb, 0.0, 1.0), 1.0);
    }
    """
}

// MARK: - MetalSceneRenderer (Triangle)
extension MetalTriangleRenderer {
    func setUniform(_ name: String, float: Float) {
        switch name {
        case "zoom": zoom = max(0.1, float)
        case "tint", "tint.r": tint.x = max(0, min(1, float))
        case "tint.g": tint.y = max(0, min(1, float))
        case "tint.b": tint.z = max(0, min(1, float))
        case "brightness": brightness = max(-1, min(1, float))
        case "exposure": exposure = max(-8, min(8, float))
        case "contrast": contrast = max(0.0, min(4.0, float))
        case "hue": hue = float
        case "saturation": saturation = max(0.0, min(2.0, float))
        case "blurStrength": blurStrength = max(0.0, min(1.0, float))
        default: break
        }
    }
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
    func vendorEvent(topic: String, data: Any?) {}
}
#endif
