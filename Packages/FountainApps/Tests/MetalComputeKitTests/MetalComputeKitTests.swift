import XCTest
@testable import MetalComputeKit
import Metal

final class MetalComputeKitTests: XCTestCase {
    private func requireMetalDevice() throws -> MTLDevice {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device present on this host — skipping compute tests.")
        }
        return dev
    }

    func testCapabilitiesReport() throws {
        _ = try requireMetalDevice()
        let caps = MetalComputeInspector.detect()
        XCTAssertTrue(caps.hasMetal)
        XCTAssertFalse(caps.deviceName.isEmpty)
        XCTAssertGreaterThan(caps.threadExecutionWidthHint, 0)
        // mpsGraphAvailable may be false depending on SDK — do not assert
    }

    func testVectorAddCorrectnessSmall() throws {
        _ = try requireMetalDevice()
        guard let ctx = MetalComputeContext() else { throw XCTSkip("MetalComputeContext unavailable") }
        let n = 4096
        var a = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)
        for i in 0..<n { a[i] = Float(i) * 0.5; b[i] = Float(i) * -0.25 }
        let out = try ctx.vadd(a: a, b: b)
        XCTAssertEqual(out.count, n)
        for i in stride(from: 0, to: n, by: n/16) {
            let expected = a[i] + b[i]
            XCTAssertEqual(out[i], expected, accuracy: 1e-6)
        }
    }

    func testVectorAddCorrectnessOddSize() throws {
        _ = try requireMetalDevice()
        guard let ctx = MetalComputeContext() else { throw XCTSkip("MetalComputeContext unavailable") }
        let n = 12_345
        let a = (0..<n).map { _ in Float.random(in: -1...1) }
        let b = (0..<n).map { _ in Float.random(in: -1...1) }
        let out = try ctx.vadd(a: a, b: b)
        XCTAssertEqual(out.count, n)
        for i in stride(from: 0, to: n, by: max(1, n/32)) {
            XCTAssertEqual(out[i], a[i]+b[i], accuracy: 1e-5)
        }
    }

    func testVectorAddLarge() throws {
        _ = try requireMetalDevice()
        guard let ctx = MetalComputeContext() else { throw XCTSkip("MetalComputeContext unavailable") }
        let n = 100_000
        let a = (0..<n).map { _ in Float.random(in: -1...1) }
        let b = (0..<n).map { _ in Float.random(in: -1...1) }
        let out = try ctx.vadd(a: a, b: b)
        XCTAssertEqual(out.count, n)
        // spot check
        for i in stride(from: 0, to: n, by: n/64) { XCTAssertEqual(out[i], a[i]+b[i], accuracy: 1e-5) }
    }

    func testSaxpyCorrectness() throws {
        _ = try requireMetalDevice()
        guard let ctx = MetalComputeContext() else { throw XCTSkip("MetalComputeContext unavailable") }
        let n = 8192
        let alpha: Float = 1.5
        let x = (0..<n).map { _ in Float.random(in: -1...1) }
        let y0 = (0..<n).map { _ in Float.random(in: -1...1) }
        let y = try ctx.saxpy(alpha: alpha, x: x, y: y0)
        XCTAssertEqual(y.count, n)
        for i in stride(from: 0, to: n, by: n/32) {
            XCTAssertEqual(y[i], alpha*x[i] + y0[i], accuracy: 1e-5)
        }
    }

    func testReduceSumCorrectness() throws {
        _ = try requireMetalDevice()
        guard let ctx = MetalComputeContext() else { throw XCTSkip("MetalComputeContext unavailable") }
        let n = 100_000
        let a = (0..<n).map { _ in Float.random(in: -1...1) }
        let gpu = try ctx.reduceSum(a)
        let cpu = a.reduce(0, +)
        XCTAssertEqual(gpu, cpu, accuracy: 1e-2)
    }

    func testMPSGraphMatmulCorrectnessIfAvailable() throws {
        _ = try requireMetalDevice()
        guard let g = MPSGraphFacade() else { throw XCTSkip("MPSGraph unavailable on this SDK") }
        let m = 32, k = 64, n = 16
        let a = (0..<(m*k)).map { _ in Float.random(in: -1...1) }
        let b = (0..<(k*n)).map { _ in Float.random(in: -1...1) }
        let c = g.matmul(a: a, m: m, k: k, b: b, n: n)
        XCTAssertEqual(c.count, m*n)
        // CPU reference
        func mmulCPU(_ a: [Float], _ b: [Float], m: Int, k: Int, n: Int) -> [Float] {
            var out = [Float](repeating: 0, count: m*n)
            for i in 0..<m {
                for j in 0..<n {
                    var acc: Float = 0
                    for t in 0..<k { acc += a[i*k + t] * b[t*n + j] }
                    out[i*n + j] = acc
                }
            }
            return out
        }
        let ref = mmulCPU(a, b, m: m, k: k, n: n)
        // Check a few elements with tolerance
        for idx in stride(from: 0, to: m*n, by: max(1, (m*n)/32)) {
            XCTAssertEqual(c[idx], ref[idx], accuracy: 1e-2)
        }
    }
}
