import Foundation
import Metal

public final class MetalComputeContext {
    public let device: MTLDevice
    public let queue: MTLCommandQueue

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let dev = device, let q = dev.makeCommandQueue() else { return nil }
        self.device = dev
        self.queue = q
    }

    // MARK: - Library / Pipeline

    public func makeLibrary(source: String, options: MTLCompileOptions? = nil) throws -> MTLLibrary {
        let opts = options ?? {
            let o = MTLCompileOptions()
            if #available(macOS 12.0, *) { o.languageVersion = .version3_0 }
            return o
        }()
        return try device.makeLibrary(source: source, options: opts)
    }

    public func makeComputePipeline(functionName: String, source: String) throws -> MTLComputePipelineState {
        let lib = try makeLibrary(source: source)
        guard let fn = lib.makeFunction(name: functionName) else { throw NSError(domain: "MetalComputeKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Function \(functionName) not found"]) }
        return try device.makeComputePipelineState(function: fn)
    }

    // MARK: - Buffers

    public func makeBuffer<T>(from array: [T], options: MTLResourceOptions = .storageModeShared) -> MTLBuffer {
        let length = array.count * MemoryLayout<T>.stride
        let buf = device.makeBuffer(length: length, options: options)!
        buf.label = "MetalComputeKit.Buffer"
        _ = array.withUnsafeBytes { ptr in memcpy(buf.contents(), ptr.baseAddress!, length) }
        return buf
    }

    public func makeEmptyBuffer<Element>(of: Element.Type, count: Int, options: MTLResourceOptions = .storageModeShared) -> MTLBuffer {
        let length = count * MemoryLayout<Element>.stride
        let buf = device.makeBuffer(length: length, options: options)!
        buf.label = "MetalComputeKit.Buffer.Empty"
        return buf
    }

    // MARK: - Dispatch helper

    public func dispatch(_ pso: MTLComputePipelineState,
                         grid: MTLSize,
                         threadsPerThreadgroup: MTLSize,
                         encode: (_ enc: MTLComputeCommandEncoder) -> Void) throws {
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { throw NSError(domain: "MetalComputeKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to make command encoder"]) }
        enc.setComputePipelineState(pso)
        encode(enc)
        enc.dispatchThreads(grid, threadsPerThreadgroup: threadsPerThreadgroup)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }
}

// MARK: - Built‑in Kernels

public enum BuiltinComputeKernels {
    // Adds two float arrays: out[i] = a[i] + b[i]
    public static let vaddMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void vadd(
        device const float* a [[buffer(0)]],
        device const float* b [[buffer(1)]],
        device float* out [[buffer(2)]],
        constant uint &n [[buffer(3)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { out[gid] = a[gid] + b[gid]; }
    }
    """
}

// MARK: - Convenience ops

public extension MetalComputeContext {
    // Vector add (Float)
    func vadd(a: [Float], b: [Float]) throws -> [Float] {
        precondition(a.count == b.count, "mismatched sizes")
        let n = UInt32(a.count)
        let pso = try makeComputePipeline(functionName: "vadd", source: BuiltinComputeKernels.vaddMSL)
        let aBuf = makeBuffer(from: a)
        let bBuf = makeBuffer(from: b)
        let outBuf = makeEmptyBuffer(of: Float.self, count: a.count)
        var nCopy = n
        let nBuf = makeBuffer(from: [nCopy])
        let tgW = min(pso.threadExecutionWidth, 256)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: a.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(aBuf, offset: 0, index: 0)
            enc.setBuffer(bBuf, offset: 0, index: 1)
            enc.setBuffer(outBuf, offset: 0, index: 2)
            enc.setBuffer(nBuf, offset: 0, index: 3)
        }
        let ptr = outBuf.contents().bindMemory(to: Float.self, capacity: a.count)
        return Array(UnsafeBufferPointer(start: ptr, count: a.count))
    }
}
