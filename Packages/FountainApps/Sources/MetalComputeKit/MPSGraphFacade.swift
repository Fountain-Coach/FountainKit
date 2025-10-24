import Foundation
import Metal

#if canImport(MetalPerformanceShadersGraph)
import MetalPerformanceShadersGraph

public final class MPSGraphFacade {
    private let graph = MPSGraph()
    private let device: MTLDevice
    private let queue: MTLCommandQueue

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let dev = device, let q = dev.makeCommandQueue() else { return nil }
        self.device = dev
        self.queue = q
    }

    // Simple A(m×k) * B(k×n) → C(m×n) with float32
    public func matmul(a: [Float], m: Int, k: Int, b: [Float], n: Int) -> [Float] {
        precondition(a.count == m*k && b.count == k*n, "dimension mismatch")
        let aShape: [NSNumber] = [m as NSNumber, k as NSNumber]
        let bShape: [NSNumber] = [k as NSNumber, n as NSNumber]

        let aTensor = graph.placeholder(shape: aShape, dataType: .float32, name: "A")
        let bTensor = graph.placeholder(shape: bShape, dataType: .float32, name: "B")
        let cTensor = graph.matrixMultiplication(aTensor, right: bTensor, name: nil)

        let desc = MPSGraphExecutableDescriptor()
        desc.options = [.synchronizeResults]

        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            aTensor: MPSGraphTensorData(device: device, data: Data(bytes: a, count: a.count*MemoryLayout<Float>.stride), shape: aShape, dataType: .float32),
            bTensor: MPSGraphTensorData(device: device, data: Data(bytes: b, count: b.count*MemoryLayout<Float>.stride), shape: bShape, dataType: .float32)
        ]
        let results = graph.run(feeds: feeds, targetTensors: [cTensor], targetOperations: nil, executionDescriptor: desc)
        guard let outData = results[cTensor]?.mpsndarray().data as Data? else { return [] }
        var out = [Float](repeating: 0, count: m*n)
        _ = out.withUnsafeMutableBytes { outData.copyBytes(to: $0) }
        return out
    }
}

#else
public final class MPSGraphFacade {
    public init?() { return nil }
}
#endif

