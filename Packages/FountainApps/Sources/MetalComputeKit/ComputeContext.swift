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

    // Multiplies two float arrays: out[i] = a[i] * b[i]
    public static let vmulMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void vmul(
        device const float* a [[buffer(0)]],
        device const float* b [[buffer(1)]],
        device float* out [[buffer(2)]],
        constant uint &n [[buffer(3)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { out[gid] = a[gid] * b[gid]; }
    }
    """

    // y[i] = alpha * x[i] + y[i]
    public static let saxpyMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void saxpy(
        constant float &alpha [[buffer(0)]],
        device const float* x [[buffer(1)]],
        device float* y [[buffer(2)]],
        constant uint &n [[buffer(3)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { y[gid] = alpha * x[gid] + y[gid]; }
    }
    """

    // Parallel block reduction: each threadgroup writes one partial sum
    public static let reduceSumBlockMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void reduce_sum_block(
        device const float* x [[buffer(0)]],
        device float* partial [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        constant uint &numGroups [[buffer(3)]],
        uint tid [[thread_index_in_threadgroup]],
        uint gid [[thread_position_in_grid]],
        uint tpg [[threads_per_threadgroup]],
        uint gtid [[threadgroup_position_in_grid]]) {
        threadgroup float sdata[256];
        float sum = 0.0f;
        // grid-stride loop
        for (uint i = gid; i < n; i += tpg * numGroups) {
            sum += x[i];
        }
        sdata[tid] = sum;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        // tree reduce
        for (uint s = tpg/2; s > 0; s >>= 1) {
            if (tid < s) { sdata[tid] += sdata[tid + s]; }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid == 0) { partial[gtid] = sdata[0]; }
    }
    """

    // Parallel block reduction: track minimum
    public static let reduceMinBlockMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void reduce_min_block(
        device const float* x [[buffer(0)]],
        device float* partial [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        constant uint &numGroups [[buffer(3)]],
        uint tid [[thread_index_in_threadgroup]],
        uint gid [[thread_position_in_grid]],
        uint tpg [[threads_per_threadgroup]],
        uint gtid [[threadgroup_position_in_grid]]) {
        threadgroup float sdata[256];
        float v = INFINITY;
        for (uint i = gid; i < n; i += tpg * numGroups) { v = fmin(v, x[i]); }
        sdata[tid] = v;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint s = tpg/2; s > 0; s >>= 1) {
            if (tid < s) { sdata[tid] = fmin(sdata[tid], sdata[tid+s]); }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid == 0) { partial[gtid] = sdata[0]; }
    }
    """

    // Parallel block reduction: track maximum
    public static let reduceMaxBlockMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void reduce_max_block(
        device const float* x [[buffer(0)]],
        device float* partial [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        constant uint &numGroups [[buffer(3)]],
        uint tid [[thread_index_in_threadgroup]],
        uint gid [[thread_position_in_grid]],
        uint tpg [[threads_per_threadgroup]],
        uint gtid [[threadgroup_position_in_grid]]) {
        threadgroup float sdata[256];
        float v = -INFINITY;
        for (uint i = gid; i < n; i += tpg * numGroups) { v = fmax(v, x[i]); }
        sdata[tid] = v;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint s = tpg/2; s > 0; s >>= 1) {
            if (tid < s) { sdata[tid] = fmax(sdata[tid], sdata[tid+s]); }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid == 0) { partial[gtid] = sdata[0]; }
    }
    """

    // Activation kernels
    public static let reluMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void relu(
        device const float* x [[buffer(0)]],
        device float* y [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { y[gid] = fmax(x[gid], 0.0f); }
    }
    """

    public static let clampMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void clampv(
        device const float* x [[buffer(0)]],
        device float* y [[buffer(1)]],
        constant float &lo [[buffer(2)]],
        constant float &hi [[buffer(3)]],
        constant uint &n [[buffer(4)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { y[gid] = clamp(x[gid], lo, hi); }
    }
    """

    public static let sigmoidMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void sigmoid(
        device const float* x [[buffer(0)]],
        device float* y [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { y[gid] = 1.0f / (1.0f + exp(-x[gid])); }
    }
    """

    // Softmax helpers
    public static let expShiftMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void exp_shift(
        device const float* x [[buffer(0)]],
        device float* y [[buffer(1)]],
        constant float &xmax [[buffer(2)]],
        constant uint &n [[buffer(3)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { y[gid] = exp(x[gid] - xmax); }
    }
    """

    public static let normalizeMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void normalize(
        device const float* x [[buffer(0)]],
        device float* y [[buffer(1)]],
        constant float &sumExp [[buffer(2)]],
        constant uint &n [[buffer(3)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) { y[gid] = x[gid] / sumExp; }
    }
    """

    // FIR convolution (same-length, zero-padded): y[i] = sum_{k=0..m-1} x[i-k] * h[k]
    public static let firConvMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void fir_conv(
        device const float* x [[buffer(0)]],
        device const float* h [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        constant uint &m [[buffer(3)]],
        device float* y [[buffer(4)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) {
            float acc = 0.0f;
            for (uint k = 0; k < m; ++k) {
                int idx = int(gid) - int(k);
                float xv = (idx >= 0 && idx < int(n)) ? x[(uint)idx] : 0.0f;
                acc += xv * h[k];
            }
            y[gid] = acc;
        }
    }
    """

    // Hann window multiply
    public static let hannWindowMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    constant float PI = 3.14159265358979323846f;
    kernel void hann_window(
        device const float* x [[buffer(0)]],
        device float* y [[buffer(1)]],
        constant uint &n [[buffer(2)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < n) {
            float coeff = 0.5f * (1.0f - cos(2.0f * PI * (float)gid / (float)(n - 1)));
            y[gid] = x[gid] * coeff;
        }
    }
    """

    // Linear resample: produce outN samples from inN
    public static let linearResampleMSL: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void linear_resample(
        device const float* x [[buffer(0)]],
        constant uint &inN [[buffer(1)]],
        constant uint &outN [[buffer(2)]],
        device float* y [[buffer(3)]],
        uint gid [[thread_position_in_grid]]) {
        if (gid < outN) {
            if (outN == 1) { y[0] = x[0]; return; }
            float t = (float)gid * (float)(inN - 1) / (float)(outN - 1);
            uint i0 = (uint)floor(t);
            uint i1 = min(i0 + 1, inN - 1);
            float frac = t - (float)i0;
            y[gid] = (1.0f - frac) * x[i0] + frac * x[i1];
        }
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
        let nBuf = makeBuffer(from: [n])
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

    // Vector multiply (Float)
    func vmul(a: [Float], b: [Float]) throws -> [Float] {
        precondition(a.count == b.count, "mismatched sizes")
        let n = UInt32(a.count)
        let pso = try makeComputePipeline(functionName: "vmul", source: BuiltinComputeKernels.vmulMSL)
        let aBuf = makeBuffer(from: a)
        let bBuf = makeBuffer(from: b)
        let outBuf = makeEmptyBuffer(of: Float.self, count: a.count)
        let nBuf = makeBuffer(from: [n])
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

    // Dot product via element-wise multiply + CPU reduction (simple & robust)
    func dot(a: [Float], b: [Float]) throws -> Float {
        let prod = try vmul(a: a, b: b)
        var acc: Float = 0
        for x in prod { acc += x }
        return acc
    }

    // SAXPY: y = alpha * x + y
    func saxpy(alpha: Float, x: [Float], y: [Float]) throws -> [Float] {
        precondition(x.count == y.count, "mismatched sizes")
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "saxpy", source: BuiltinComputeKernels.saxpyMSL)
        let xBuf = makeBuffer(from: x)
        let yBuf = makeBuffer(from: y)
        let aBuf = makeBuffer(from: [alpha])
        let nBuf = makeBuffer(from: [n])
        let tgW = min(pso.threadExecutionWidth, 256)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: x.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(aBuf, offset: 0, index: 0)
            enc.setBuffer(xBuf, offset: 0, index: 1)
            enc.setBuffer(yBuf, offset: 0, index: 2)
            enc.setBuffer(nBuf, offset: 0, index: 3)
        }
        let ptr = yBuf.contents().bindMemory(to: Float.self, capacity: x.count)
        return Array(UnsafeBufferPointer(start: ptr, count: x.count))
    }

    // Reduction sum using block reduction to partial buffer, then CPU sum of partials
    func reduceSum(_ x: [Float]) throws -> Float {
        guard !x.isEmpty else { return 0 }
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "reduce_sum_block", source: BuiltinComputeKernels.reduceSumBlockMSL)
        let xBuf = makeBuffer(from: x)
        let tgW = min(256, pso.threadExecutionWidth)
        // Choose number of threadgroups ~ ceil(n / (tgW * 4)) bounded
        let groups = max(1, min((x.count + tgW - 1)/tgW, 1024))
        let partialBuf = makeEmptyBuffer(of: Float.self, count: groups)
        let nBuf = makeBuffer(from: [n])
        let grid = MTLSize(width: tgW * groups, height: 1, depth: 1)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(partialBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
            let groupsBuf = makeBuffer(from: [UInt32(groups)])
            enc.setBuffer(groupsBuf, offset: 0, index: 3)
        }
        // CPU fold the partials
        let ptr = partialBuf.contents().bindMemory(to: Float.self, capacity: groups)
        var sum: Float = 0
        for i in 0..<groups { sum += ptr[i] }
        return sum
    }

    func reduceMin(_ x: [Float]) throws -> Float {
        guard !x.isEmpty else { return .infinity }
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "reduce_min_block", source: BuiltinComputeKernels.reduceMinBlockMSL)
        let xBuf = makeBuffer(from: x)
        let tgW = min(256, pso.threadExecutionWidth)
        let groups = max(1, min((x.count + tgW - 1)/tgW, 1024))
        let partialBuf = makeEmptyBuffer(of: Float.self, count: groups)
        let nBuf = makeBuffer(from: [n])
        let grid = MTLSize(width: tgW * groups, height: 1, depth: 1)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(partialBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
            let groupsBuf = makeBuffer(from: [UInt32(groups)])
            enc.setBuffer(groupsBuf, offset: 0, index: 3)
        }
        let ptr = partialBuf.contents().bindMemory(to: Float.self, capacity: groups)
        var v = Float.infinity
        for i in 0..<groups { v = min(v, ptr[i]) }
        return v
    }

    func reduceMax(_ x: [Float]) throws -> Float {
        guard !x.isEmpty else { return -.infinity }
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "reduce_max_block", source: BuiltinComputeKernels.reduceMaxBlockMSL)
        let xBuf = makeBuffer(from: x)
        let tgW = min(256, pso.threadExecutionWidth)
        let groups = max(1, min((x.count + tgW - 1)/tgW, 1024))
        let partialBuf = makeEmptyBuffer(of: Float.self, count: groups)
        let nBuf = makeBuffer(from: [n])
        let grid = MTLSize(width: tgW * groups, height: 1, depth: 1)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(partialBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
            let groupsBuf = makeBuffer(from: [UInt32(groups)])
            enc.setBuffer(groupsBuf, offset: 0, index: 3)
        }
        let ptr = partialBuf.contents().bindMemory(to: Float.self, capacity: groups)
        var v = -Float.infinity
        for i in 0..<groups { v = max(v, ptr[i]) }
        return v
    }

    func relu(_ x: [Float]) throws -> [Float] {
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "relu", source: BuiltinComputeKernels.reluMSL)
        let xBuf = makeBuffer(from: x)
        let yBuf = makeEmptyBuffer(of: Float.self, count: x.count)
        let nBuf = makeBuffer(from: [n])
        let tgW = min(256, pso.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: x.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(yBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
        }
        let ptr = yBuf.contents().bindMemory(to: Float.self, capacity: x.count)
        return Array(UnsafeBufferPointer(start: ptr, count: x.count))
    }

    func clamp(_ x: [Float], min lo: Float, max hi: Float) throws -> [Float] {
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "clampv", source: BuiltinComputeKernels.clampMSL)
        let xBuf = makeBuffer(from: x)
        let yBuf = makeEmptyBuffer(of: Float.self, count: x.count)
        let loBuf = makeBuffer(from: [lo])
        let hiBuf = makeBuffer(from: [hi])
        let nBuf = makeBuffer(from: [n])
        let tgW = min(256, pso.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: x.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(yBuf, offset: 0, index: 1)
            enc.setBuffer(loBuf, offset: 0, index: 2)
            enc.setBuffer(hiBuf, offset: 0, index: 3)
            enc.setBuffer(nBuf, offset: 0, index: 4)
        }
        let ptr = yBuf.contents().bindMemory(to: Float.self, capacity: x.count)
        return Array(UnsafeBufferPointer(start: ptr, count: x.count))
    }

    func sigmoid(_ x: [Float]) throws -> [Float] {
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "sigmoid", source: BuiltinComputeKernels.sigmoidMSL)
        let xBuf = makeBuffer(from: x)
        let yBuf = makeEmptyBuffer(of: Float.self, count: x.count)
        let nBuf = makeBuffer(from: [n])
        let tgW = min(256, pso.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: x.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(yBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
        }
        let ptr = yBuf.contents().bindMemory(to: Float.self, capacity: x.count)
        return Array(UnsafeBufferPointer(start: ptr, count: x.count))
    }

    func softmax(_ x: [Float]) throws -> [Float] {
        guard !x.isEmpty else { return [] }
        let xmax = try reduceMax(x)
        // exp shifted
        let n = UInt32(x.count)
        let expPSO = try makeComputePipeline(functionName: "exp_shift", source: BuiltinComputeKernels.expShiftMSL)
        let xBuf = makeBuffer(from: x)
        let expBuf = makeEmptyBuffer(of: Float.self, count: x.count)
        let xmaxBuf = makeBuffer(from: [xmax])
        let nBuf = makeBuffer(from: [n])
        let tgW = min(256, expPSO.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: x.count, height: 1, depth: 1)
        try dispatch(expPSO, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(expBuf, offset: 0, index: 1)
            enc.setBuffer(xmaxBuf, offset: 0, index: 2)
            enc.setBuffer(nBuf, offset: 0, index: 3)
        }
        // sum of exp
        let sumExp = try reduceSum(Array(UnsafeBufferPointer(start: expBuf.contents().bindMemory(to: Float.self, capacity: x.count), count: x.count)))
        // normalize
        let normPSO = try makeComputePipeline(functionName: "normalize", source: BuiltinComputeKernels.normalizeMSL)
        let sumBuf = makeBuffer(from: [sumExp])
        let outBuf = makeEmptyBuffer(of: Float.self, count: x.count)
        try dispatch(normPSO, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(expBuf, offset: 0, index: 0)
            enc.setBuffer(outBuf, offset: 0, index: 1)
            enc.setBuffer(sumBuf, offset: 0, index: 2)
            enc.setBuffer(nBuf, offset: 0, index: 3)
        }
        let ptr = outBuf.contents().bindMemory(to: Float.self, capacity: x.count)
        return Array(UnsafeBufferPointer(start: ptr, count: x.count))
    }

    // FIR convolution (same-length, zero-padded)
    func firConvolve(signal: [Float], taps: [Float]) throws -> [Float] {
        guard !signal.isEmpty, !taps.isEmpty else { return signal }
        let n = UInt32(signal.count)
        let m = UInt32(taps.count)
        let pso = try makeComputePipeline(functionName: "fir_conv", source: BuiltinComputeKernels.firConvMSL)
        let xBuf = makeBuffer(from: signal)
        let hBuf = makeBuffer(from: taps)
        let nBuf = makeBuffer(from: [n])
        let mBuf = makeBuffer(from: [m])
        let yBuf = makeEmptyBuffer(of: Float.self, count: signal.count)
        let tgW = min(256, pso.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: signal.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(hBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
            enc.setBuffer(mBuf, offset: 0, index: 3)
            enc.setBuffer(yBuf, offset: 0, index: 4)
        }
        let ptr = yBuf.contents().bindMemory(to: Float.self, capacity: signal.count)
        return Array(UnsafeBufferPointer(start: ptr, count: signal.count))
    }

    // Hann window
    func hannWindow(_ x: [Float]) throws -> [Float] {
        guard !x.isEmpty else { return [] }
        let n = UInt32(x.count)
        let pso = try makeComputePipeline(functionName: "hann_window", source: BuiltinComputeKernels.hannWindowMSL)
        let xBuf = makeBuffer(from: x)
        let yBuf = makeEmptyBuffer(of: Float.self, count: x.count)
        let nBuf = makeBuffer(from: [n])
        let tgW = min(256, pso.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: x.count, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(xBuf, offset: 0, index: 0)
            enc.setBuffer(yBuf, offset: 0, index: 1)
            enc.setBuffer(nBuf, offset: 0, index: 2)
        }
        let ptr = yBuf.contents().bindMemory(to: Float.self, capacity: x.count)
        return Array(UnsafeBufferPointer(start: ptr, count: x.count))
    }

    // Linear resample
    func linearResample(signal: [Float], outCount: Int) throws -> [Float] {
        guard outCount > 0, !signal.isEmpty else { return [] }
        let inN = UInt32(signal.count)
        let outN = UInt32(outCount)
        let pso = try makeComputePipeline(functionName: "linear_resample", source: BuiltinComputeKernels.linearResampleMSL)
        let inBuf = makeBuffer(from: signal)
        let inNBuf = makeBuffer(from: [inN])
        let outNBuf = makeBuffer(from: [outN])
        let outBuf = makeEmptyBuffer(of: Float.self, count: outCount)
        let tgW = min(256, pso.threadExecutionWidth)
        let tg = MTLSize(width: tgW, height: 1, depth: 1)
        let grid = MTLSize(width: outCount, height: 1, depth: 1)
        try dispatch(pso, grid: grid, threadsPerThreadgroup: tg) { enc in
            enc.setBuffer(inBuf, offset: 0, index: 0)
            enc.setBuffer(inNBuf, offset: 0, index: 1)
            enc.setBuffer(outNBuf, offset: 0, index: 2)
            enc.setBuffer(outBuf, offset: 0, index: 3)
        }
        let ptr = outBuf.contents().bindMemory(to: Float.self, capacity: outCount)
        return Array(UnsafeBufferPointer(start: ptr, count: outCount))
    }
}
