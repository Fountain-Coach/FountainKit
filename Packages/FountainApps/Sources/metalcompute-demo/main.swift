import Foundation
import MetalComputeKit

@main
struct MetalComputeDemo {
    static func main() {
        print("[capabilities]\n\(MetalComputeInspector.report())\n")
        guard let ctx = MetalComputeContext() else {
            fputs("[compute-demo] No Metal device available\n", stderr)
            exit(1)
        }
        print("[compute-demo] Device: \(ctx.device.name)")

        // MARK: - vadd benchmark
        do {
            let n = 1_000_000
            let a = (0..<n).map { _ in Float.random(in: -1...1) }
            let b = (0..<n).map { _ in Float.random(in: -1...1) }
            _ = try ctx.vadd(a: Array(a.prefix(1024)), b: Array(b.prefix(1024))) // warm-up (compile pipeline)
            let t0 = CFAbsoluteTimeGetCurrent()
            let out = try ctx.vadd(a: a, b: b)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            print(String(format: "[vadd] n=%d elapsed=%.2f ms  sample=[%.3f, %.3f, %.3f]", n, ms, out[0], out[1], out[2]))
        } catch {
            fputs("[compute-demo] vadd failed: \(error)\n", stderr)
        }

        // MARK: - MPSGraph matmul benchmark (if available)
        #if canImport(MetalPerformanceShadersGraph)
        if let g = MPSGraphFacade() {
            let m = 128, k = 128, n = 128
            let a = (0..<(m*k)).map { _ in Float.random(in: -1...1) }
            let b = (0..<(k*n)).map { _ in Float.random(in: -1...1) }
            _ = g.matmul(a: Array(a.prefix(64)), m: 8, k: 8, b: Array(b.prefix(64)), n: 8) // warm-up
            let t0 = CFAbsoluteTimeGetCurrent()
            let c = g.matmul(a: a, m: m, k: k, b: b, n: n)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            if c.count >= 3 {
                print(String(format: "[mpsgraph.matmul] %dx%dx%d elapsed=%.2f ms  sample=[%.3f, %.3f, %.3f]", m, k, n, ms, c[0], c[1], c[2]))
            } else {
                print(String(format: "[mpsgraph.matmul] %dx%dx%d elapsed=%.2f ms", m, k, n, ms))
            }
        } else {
            print("[mpsgraph.matmul] MPSGraph not available on this host")
        }
        #else
        print("[mpsgraph.matmul] MPSGraph not available in this build")
        #endif
    }
}
