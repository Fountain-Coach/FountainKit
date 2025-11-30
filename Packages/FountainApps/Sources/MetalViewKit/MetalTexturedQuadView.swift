// Embeddable Metal view rendering a textured quad with depth + uniforms

#if canImport(SwiftUI) && canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import SwiftUI
import AppKit
import Metal
import MetalKit

public struct MetalTexturedQuadView: NSViewRepresentable {
    private let image: NSImage?
    private let rotationSpeed: Float
    private let onReady: MetalSceneOnReady?
    private let instrument: MetalInstrumentDescriptor?

    public init(image: NSImage? = nil, rotationSpeed: Float = 0.35, onReady: MetalSceneOnReady? = nil) {
        self.image = image
        self.rotationSpeed = rotationSpeed
        self.onReady = onReady
        self.instrument = nil
    }

    public init(image: NSImage? = nil, rotationSpeed: Float = 0.35, onReady: MetalSceneOnReady? = nil, instrument: MetalInstrumentDescriptor?) {
        self.image = image
        self.rotationSpeed = rotationSpeed
        self.onReady = onReady
        self.instrument = instrument
    }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

        let device = view.device ?? MTLCreateSystemDefaultDevice()
        let renderer = MetalTexturedQuadRenderer(device: device,
                                                 colorFormat: view.colorPixelFormat,
                                                 depthFormat: view.depthStencilPixelFormat,
                                                 image: image,
                                                 rotationSpeed: rotationSpeed)
        context.coordinator.renderer = renderer
        view.delegate = renderer
        if let r = renderer { onReady?(r) }
        if let r = renderer, let instrument = instrument {
            let inst = MetalInstrument(sink: r, descriptor: instrument)
            inst.enable()
            context.coordinator.instrument = inst
        }
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        // Propagate rotation updates from SwiftUI
        context.coordinator.renderer?.rotationSpeed = rotationSpeed
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        fileprivate var renderer: MetalTexturedQuadRenderer?
        fileprivate var instrument: MetalInstrument?
    }
}

final class MetalTexturedQuadRenderer: NSObject, MTKViewDelegate, MetalSceneRenderer, MetalSceneUniformControls {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    private var texture: MTLTexture!
    private var sampler: MTLSamplerState!
    private var time: Float = 0
    var rotationSpeed: Float
    private var zoom: Float = 1.0
    private var tint: SIMD3<Float> = .init(repeating: 1)
    private var brightness: Float = 0.0
    private var exposure: Float = 0.0
    private var contrast: Float = 1.0
    private var hue: Float = 0.0
    private var saturation: Float = 1.0
    private var blurStrength: Float = 0.0

    init?(device: MTLDevice?, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat, image: NSImage?, rotationSpeed: Float) {
        guard let device = device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        self.rotationSpeed = rotationSpeed

        super.init()
        do {
            try buildPipeline(colorFormat: colorFormat, depthFormat: depthFormat)
            buildGeometry()
            buildUniforms()
            buildTexture(from: image)
            buildSampler()
        } catch {
            print("[MetalViewKit] Failed to init textured renderer: \(error)")
            return nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }

        // Update uniforms (angle + aspect + zoom/tint)
        time += 1.0 / Float(view.preferredFramesPerSecond > 0 ? view.preferredFramesPerSecond : 60)
        let w = max(1.0, Float(view.drawableSize.width))
        let h = max(1.0, Float(view.drawableSize.height))
        var uniforms = Uniforms(
            angle: time * rotationSpeed,
            aspect: h / w,
            zoom: zoom,
            pad0: 0,
            tint: tint,
            brightness: brightness,
            exposure: exposure,
            contrast: contrast,
            hue: hue,
            saturation: saturation,
            blurStrength: blurStrength,
            pad1: 0
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)

        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        enc.endEncoding()

        cb.present(drawable)
        cb.commit()
    }

    // MARK: - MetalSceneUniformControls

    // MARK: - MetalSceneRenderer
    func vendorEvent(topic: String, data: Any?) {}

    private func buildPipeline(colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) throws {
        let src = Self.inlineMetalSource
        let options = MTLCompileOptions()
        if #available(macOS 12.0, *) { options.languageVersion = .version3_0 }
        let lib = try device.makeLibrary(source: src, options: options)

        let vfn = lib.makeFunction(name: "textured_quad_vs")
        let ffn = lib.makeFunction(name: "textured_quad_ps")
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = colorFormat
        desc.depthAttachmentPixelFormat = depthFormat
        pipelineState = try device.makeRenderPipelineState(descriptor: desc)

        let d = MTLDepthStencilDescriptor()
        d.isDepthWriteEnabled = true
        d.depthCompareFunction = .less
        depthState = device.makeDepthStencilState(descriptor: d)
    }

    private func buildGeometry() {
        struct Vertex { var position: SIMD3<Float>; var uv: SIMD2<Float> }
        // A unit quad rotated by uniforms; z varies to exercise depth
        let z0: Float = 0.1, z1: Float = 0.2
        let vertices: [Vertex] = [
            .init(position: [-0.6, -0.6, z0], uv: [0, 1]),
            .init(position: [ 0.6, -0.6, z1], uv: [1, 1]),
            .init(position: [ 0.6,  0.6, z0], uv: [1, 0]),
            .init(position: [-0.6,  0.6, z1], uv: [0, 0]),
        ]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]

        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)
        vertexBuffer.label = "MetalViewKit.TexturedQuadVertices"
        indexBuffer.label = "MetalViewKit.TexturedQuadIndices"
    }

    private func buildUniforms() {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)
        uniformBuffer.label = "MetalViewKit.Uniforms"
    }

    private func buildSampler() {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .notMipmapped
        d.sAddressMode = .repeat
        d.tAddressMode = .repeat
        sampler = device.makeSamplerState(descriptor: d)
    }

    private func buildTexture(from image: NSImage?) {
        if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            texture = makeTexture(from: cg)
            return
        }
        // Fallback: 64x64 checkerboard
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let c: UInt8 = (((x / 8) + (y / 8)) % 2 == 0) ? 220 : 40
                let i = (y * size + x) * 4
                pixels[i + 0] = c
                pixels[i + 1] = c
                pixels[i + 2] = 255
                pixels[i + 3] = 255
            }
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        texture = device.makeTexture(descriptor: desc)
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
    }

    private func makeTexture(from cgImage: CGImage) -> MTLTexture {
        let width = cgImage.width, height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var raw = [UInt8](repeating: 0, count: Int(bytesPerRow * height))
        guard let ctx = CGContext(data: &raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("[MetalViewKit] Failed to create CGContext for texture upload")
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        let tex = device.makeTexture(descriptor: desc)!
        tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: raw, bytesPerRow: bytesPerRow)
        return tex
    }

    struct Uniforms {
        var angle: Float; var aspect: Float; var zoom: Float; var pad0: Float
        var tint: SIMD3<Float>
        var brightness: Float; var exposure: Float; var contrast: Float; var hue: Float; var saturation: Float; var blurStrength: Float; var pad1: Float
    }

    // Inline Metal Shaders: textured quad with rotation around Z using a simple 2D rotation
    private static let inlineMetalSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VSIn {
        float3 position [[attribute(0)]];
        float2 uv       [[attribute(1)]];
    };
    struct VSOut {
        float4 position [[position]];
        float2 uv;
    };
    struct Uniforms { float angle; float aspect; float zoom; float pad0; float3 tint; float brightness; float exposure; float contrast; float hue; float saturation; float blurStrength; float pad1; };

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

    vertex VSOut textured_quad_vs(uint vid [[vertex_id]],
                                  const device VSIn *inVerts [[buffer(0)]],
                                  constant Uniforms &u [[buffer(1)]]) {
        VSIn v = inVerts[vid];
        float c = cos(u.angle), s = sin(u.angle);
        float2 r = float2(
            v.position.x * c - v.position.y * s,
            v.position.x * s + v.position.y * c
        );
        VSOut out;
        out.position = float4(r.x * u.aspect * u.zoom, r.y * u.zoom, v.position.z, 1.0);
        out.uv = v.uv;
        return out;
    }

    fragment float4 textured_quad_ps(VSOut in [[stage_in]],
                                     constant Uniforms &u [[buffer(0)]],
                                     texture2d<float> colorTex [[texture(0)]],
                                     sampler s [[sampler(0)]]) {
        float4 c = colorTex.sample(s, in.uv);
        float3 rgb = c.rgb * u.tint;
        rgb = apply_brightness(rgb, u.brightness);
        rgb = apply_exposure(rgb, u.exposure);
        rgb = apply_contrast(rgb, u.contrast);
        rgb = apply_saturation(rgb, u.saturation);
        rgb = apply_hue(rgb, u.hue);
        // Simple 5-tap blur mix controlled by blurStrength (0..1); fixed UV offsets
        if (u.blurStrength > 0.001) {
            float2 off = float2(0.002, 0.002);
            float3 b = 0.2 * ( colorTex.sample(s, in.uv).rgb
                             + colorTex.sample(s, in.uv + off).rgb
                             + colorTex.sample(s, in.uv - off).rgb
                             + colorTex.sample(s, in.uv + float2(off.x, -off.y)).rgb
                             + colorTex.sample(s, in.uv + float2(-off.x, off.y)).rgb );
            rgb = mix(rgb, b, clamp(u.blurStrength, 0.0, 1.0));
        }
        return float4(clamp(rgb, 0.0, 1.0), 1.0);
    }
    """
}

// MARK: - MetalSceneRenderer conformance (Textured Quad)
extension MetalTexturedQuadRenderer {
    func setUniform(_ name: String, float: Float) {
        switch name {
        case "rotationSpeed": self.rotationSpeed = float
        case "zoom": self.zoom = max(0.1, float)
        case "tint", "tint.r": self.tint.x = max(0, min(1, float))
        case "tint.g": self.tint.y = max(0, min(1, float))
        case "tint.b": self.tint.z = max(0, min(1, float))
        case "brightness": self.brightness = max(-1, min(1, float))
        case "exposure": self.exposure = max(-8, min(8, float))
        case "contrast": self.contrast = max(0.0, min(4.0, float))
        case "hue": self.hue = float // radians
        case "saturation": self.saturation = max(0.0, min(2.0, float))
        case "blurStrength": self.blurStrength = max(0.0, min(1.0, float))
        case "textureIndex": break // placeholder for future multi-texture support
        default: break
        }
    }
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {
        let norm = max(0.0, min(1.0, Float(velocity) / 127.0))
        self.rotationSpeed = 0.05 + norm * 1.15
    }
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {
        if controller == 1 { // Mod wheel
            let norm = max(0.0, min(1.0, Float(value) / 127.0))
            self.rotationSpeed = 0.05 + norm * 1.15
        }
    }
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {
        let norm = max(0.0, min(1.0, Float(value14) / 16383.0))
        self.rotationSpeed = 0.05 + norm * 1.15
    }
}
#endif
