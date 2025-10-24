import Foundation
import Metal

import MetalPerformanceShaders

public final class MPSGraphFacade {
    private let graph = MPSGraph()
    private let device: MTLDevice

    public init?() {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = dev
    }

    // A(m×k) * B(k×n) → C(m×n)
    public func matmul(a: [Float], m: Int, k: Int, b: [Float], n: Int) -> [Float] {
        precondition(a.count == m*k && b.count == k*n, "dimension mismatch")
        let aShape: [NSNumber] = [m as NSNumber, k as NSNumber]
        let bShape: [NSNumber] = [k as NSNumber, n as NSNumber]

        // Placeholders
        let aTensor = graph.placeholder(shape: aShape, dataType: .float32, name: "A")
        let bTensor = graph.placeholder(shape: bShape, dataType: .float32, name: "B")
        let cTensor = graph.matrixMultiplication(primary: aTensor, secondary: bTensor, name: nil)

        // MPSNDArray feeds
        let aDesc = MPSNDArrayDescriptor(dataType: .float32, shape: aShape)
        let bDesc = MPSNDArrayDescriptor(dataType: .float32, shape: bShape)
        let aArr = MPSNDArray(device: device, descriptor: aDesc)
        let bArr = MPSNDArray(device: device, descriptor: bDesc)
        a.withUnsafeBytes { p in aArr.writeBytes(p.baseAddress!, strideBytes: nil) }
        b.withUnsafeBytes { p in bArr.writeBytes(p.baseAddress!, strideBytes: nil) }
        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            aTensor: MPSGraphTensorData(mpsndarray: aArr),
            bTensor: MPSGraphTensorData(mpsndarray: bArr)
        ]

        let results = graph.run(feeds: feeds, targetTensors: [cTensor], targetOperations: nil)
        guard let outArr = results[cTensor]?.mpsndarray() else { return [] }
        var out = [Float](repeating: 0, count: m*n)
        out.withUnsafeMutableBytes { outArr.readBytes($0.baseAddress!, strideBytes: nil) }
        return out
    }
}
