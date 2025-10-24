import Foundation
import Metal

#if canImport(MetalPerformanceShadersGraph)
import MetalPerformanceShadersGraph
private let _mpsGraphAvailable: Bool = true
#else
private let _mpsGraphAvailable: Bool = false
#endif

public struct MetalComputeCapabilities: Sendable {
    public let hasMetal: Bool
    public let deviceName: String
    public let threadExecutionWidthHint: Int
    public let mpsGraphAvailable: Bool
}

public enum MetalComputeInspector {
    /// Detects basic compute capabilities on this host.
    public static func detect() -> MetalComputeCapabilities {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            return MetalComputeCapabilities(hasMetal: false, deviceName: "(no device)", threadExecutionWidthHint: 0, mpsGraphAvailable: false)
        }
        // Try to infer a useful threadExecutionWidth by compiling the built‑in vadd kernel.
        var width = 32
        do {
            let ctx = MetalComputeContext(device: dev)!
            let pso = try ctx.makeComputePipeline(functionName: "vadd", source: BuiltinComputeKernels.vaddMSL)
            width = pso.threadExecutionWidth
        } catch {
            // Keep default
        }
        return MetalComputeCapabilities(hasMetal: true, deviceName: dev.name, threadExecutionWidthHint: width, mpsGraphAvailable: _mpsGraphAvailable)
    }

    /// Formats a human‑readable report string summarizing capabilities.
    public static func report() -> String {
        let c = detect()
        var lines: [String] = []
        lines.append("Metal Device: \(c.deviceName)")
        lines.append("Metal Available: \(c.hasMetal ? "yes" : "no")")
        lines.append(String(format: "Thread Execution Width (hint): %d", c.threadExecutionWidthHint))
        lines.append("MPSGraph Available: \(c.mpsGraphAvailable ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }
}

