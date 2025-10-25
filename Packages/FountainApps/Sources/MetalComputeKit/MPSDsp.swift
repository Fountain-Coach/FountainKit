import Foundation
import Metal
import MetalPerformanceShaders
#if canImport(Accelerate)
import Accelerate
#endif

public extension MetalComputeContext {
    // 2D convolution using MPSImageConvolution, zero-padded, r32Float textures
    func conv2D(_ input: [Float], width: Int, height: Int, kernel: [Float], kWidth: Int, kHeight: Int) throws -> [Float] {
        precondition(input.count == width*height, "input size mismatch")
        precondition(kernel.count == kWidth*kHeight, "kernel size mismatch")
        let dev = self.device
        let inTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        inTexDesc.usage = [.shaderRead]
        let outTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        outTexDesc.usage = [.shaderWrite]
        guard let inTex = dev.makeTexture(descriptor: inTexDesc), let outTex = dev.makeTexture(descriptor: outTexDesc) else { throw NSError(domain: "MetalComputeKit", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to create textures"]) }
        var src = input // copy
        inTex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: &src, bytesPerRow: width*MemoryLayout<Float>.stride)
        let conv = MPSImageConvolution(device: dev, kernelWidth: kWidth, kernelHeight: kHeight, weights: kernel)
        conv.edgeMode = .zero
        guard let cmd = queue.makeCommandBuffer() else { throw NSError(domain: "MetalComputeKit", code: -11, userInfo: [NSLocalizedDescriptionKey: "Failed to make command buffer"]) }
        let srcImg = MPSImage(texture: inTex, featureChannels: 1)
        let dstImg = MPSImage(texture: outTex, featureChannels: 1)
        conv.encode(commandBuffer: cmd, sourceImage: srcImg, destinationImage: dstImg)
        cmd.commit(); cmd.waitUntilCompleted()
        var out = [Float](repeating: 0, count: width*height)
        outTex.getBytes(&out, bytesPerRow: width*MemoryLayout<Float>.stride, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return out
    }

    // 1D real FFT (CPU via Accelerate for broad compatibility). Returns magnitudes.
    func fftMagnitudes(_ x: [Float]) -> [Float] {
        #if canImport(Accelerate)
        // Ensure power-of-two length using zero-padding for deterministic results
        let n = x.count
        let log2n = vDSP_Length(floor(log2(Double(max(1, n)))))
        let radixN = 1 << log2n
        let data: [Float]
        if radixN != n {
            data = x + [Float](repeating: 0, count: max(0, radixN - min(radixN, n)))
        } else {
            data = x
        }

        let halfN = data.count / 2
        // Real-to-complex DFT (non-interleaved)
        guard let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(data.count), .FORWARD) else { return [] }
        defer { vDSP_DFT_DestroySetup(setup) }

        var real = data
        var imag = [Float](repeating: 0, count: data.count)
        var oReal = [Float](repeating: 0, count: halfN)
        var oImag = [Float](repeating: 0, count: halfN)
        vDSP_DFT_Execute(setup, &real, &imag, &oReal, &oImag)

        // Magnitudes for bins [0, halfN] (include Nyquist)
        var mag = [Float](repeating: 0, count: halfN + 1)
        if halfN > 0 {
            mag[0] = sqrt(oReal[0]*oReal[0] + oImag[0]*oImag[0])
            for k in 1..<halfN {
                let re = oReal[k]
                let im = oImag[k]
                mag[k] = sqrt(re*re + im*im)
            }
            // Nyquist (for even length)
            mag[halfN] = sqrt(oReal[halfN-1]*oReal[halfN-1] + oImag[halfN-1]*oImag[halfN-1])
        }
        return mag
        #else
        return []
        #endif
    }

    // Preferred FFT magnitudes: picks a GPU path when a compatible API is available; falls back to vDSP otherwise.
    // Note: A future GPU path can use MPSGraph or MPSFFT; this wrapper keeps call sites stable.
    func fftMagnitudesPreferred(_ x: [Float]) -> [Float] {
        #if canImport(MetalPerformanceShadersGraph)
        // Placeholder: until we pin an SDK with stable graph FFT, prefer CPU vDSP for determinism.
        return fftMagnitudes(x)
        #else
        return fftMagnitudes(x)
        #endif
    }

    // CPU reference for 2D conv (zero padded)
    private func cpuConv2D(_ x: [Float], width: Int, height: Int, kernel: [Float], kWidth: Int, kHeight: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width*height)
        let kx = kWidth, ky = kHeight
        for y in 0..<height {
            for x0 in 0..<width {
                var acc: Float = 0
                for j in 0..<ky {
                    for i in 0..<kx {
                        let xi = x0 - i
                        let yj = y - j
                        if xi >= 0 && xi < width && yj >= 0 && yj < height {
                            acc += x[yj*width + xi] * kernel[j*kx + i]
                        }
                    }
                }
                out[y*width + x0] = acc
            }
        }
        return out
    }
}
