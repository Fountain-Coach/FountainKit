import XCTest
@testable import pbvrt_server
import CoreGraphics

final class ProbesUnitTests: XCTestCase {
    func testResize1DAndCosine() throws {
        let a: [Float] = [0, 1, 0, -1]
        let b = PBVRTHandlers.resize1D(a, to: 8)
        XCTAssertEqual(b.count, 8)
        // Cosine distance of identical vectors ~ 0
        let d = PBVRTHandlers.cosineDistance(a: b, b: b)
        XCTAssertLessThanOrEqual(d, 1e-6)
    }

    func testSaliencyGradientNonZero() throws {
        // Create a simple gradient grayscale buffer (edge in the middle)
        let w = 64, h = 64
        var g = [Float](repeating: 0, count: w*h)
        for y in 0..<h { for x in 0..<w { g[y*w + x] = x < (w/2) ? 0 : 1 } }
        let s = PBVRTHandlers.saliencyMap(fromGrayscale: g, width: w, height: h)
        // Expect some non-zero saliency near the edge
        let sum = s.reduce(0, +)
        XCTAssertGreaterThan(sum, 0)
    }

    func testEstimateTranslation() throws {
        // Build a tiny image with a bright square and translate it
        let size = 64
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return XCTFail("no cs") }
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        // Draw a white square at (16,16)-(32,32)
        for y in 16..<32 {
            for x in 16..<32 {
                let idx = y*bytesPerRow + x*4
                pixels[idx+0] = 255
                pixels[idx+1] = 255
                pixels[idx+2] = 255
                pixels[idx+3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        guard let base = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return XCTFail("no cg") }
        // Translate by (dx,dy) = (5, -3)
        let dx = 5, dy = -3
        guard let shifted = CGImage.translate(image: base, by: CGSize(width: dx, height: dy)) else { return XCTFail("no shifted") }
        let (estX, estY, _) = PBVRTHandlers.estimateTranslation(baseline: base, candidate: shifted, sample: 64, search: 10)
        // Allow sign ambiguity in Y due to coordinate convention; magnitude should match
        XCTAssertEqual(estX, dx, "dx mismatch")
        XCTAssertEqual(abs(estY), abs(dy), "|dy| mismatch")
    }

    func testSpectrogramIdenticalLowL2() throws {
        // Two identical 440 Hz sine waves -> very low L2
        let sr: Double = 16000
        let dur: Double = 0.25
        let n = Int(sr * dur)
        let f: Double = 440
        var a = [Float](repeating: 0, count: n)
        for i in 0..<n { a[i] = Float(sin(2*Double.pi*f*Double(i)/sr)) }
        let (ma, _) = PBVRTHandlers.spectrogram(samples: a, sampleRate: sr)
        let (mb, _) = PBVRTHandlers.spectrogram(samples: a, sampleRate: sr)
        let rows = min(ma.rows, mb.rows), cols = min(ma.cols, mb.cols)
        let l2 = PBVRTHandlers.l2Distance(a: ma, b: mb, rows: rows, cols: cols)
        XCTAssertLessThan(l2, 1e-3)
    }
}
