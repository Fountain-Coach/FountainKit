import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class PixelGridVerifierTests: XCTestCase {
    func testMinorGridSpacingMatchesPixelsWithinTolerance() throws {
        let vm = EditorVM()
        vm.zoom = 1.0
        vm.translation = .zero
        vm.grid = 12

        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)

        let h = Int(host.bounds.height)
        let w = Int(host.bounds.width)
        let scale = max(1.0, Double(rep.pixelsWide) / Double(w))

        // Detect vertical grid lines by brightness gradient
        func brightness(_ c: NSColor?) -> Double {
            guard let c else { return 0 }
            let cc = c.usingColorSpace(.deviceRGB) ?? c
            return Double((cc.redComponent + cc.greenComponent + cc.blueComponent) / 3.0)
        }
        var diffs: [Double] = []
        let sampleRows = stride(from: max(2, h / 5), through: h - 2, by: max(8, h / 6))
        for y in sampleRows {
            var prevBrightness: Double = 0
            var edges: [Int] = []
            for x in 1..<w {
                let b = brightness(rep.colorAt(x: x, y: y))
                let db = abs(b - prevBrightness)
                if db > 0.08 { // robust threshold for grid line transitions
                    edges.append(x)
                }
                prevBrightness = b
            }
            let pixelDiffs = zip(edges, edges.dropFirst()).map { Double($1 - $0) / scale }
            let rowDiffs = pixelDiffs.filter { $0 > 6 && $0 < 60 }
            diffs.append(contentsOf: rowDiffs)
        }
        guard diffs.count > 5 else { throw XCTSkip("insufficient edges to measure grid spacing across sampled rows") }
        let sorted = diffs.sorted()
        let median = sorted[sorted.count/2]

        // Expected minor spacing in view pixels
        let expected = Double(CGFloat(vm.grid) * vm.zoom)
        XCTAssertEqual(median, expected, accuracy: 2.0, "minor grid spacing off: median=\(median) expected=\(expected)")
    }

    func testMinorGridSpacingRespectsZoomAndTranslation() throws {
        let vm = EditorVM()
        vm.zoom = 1.75
        vm.translation = CGPoint(x: 13, y: -7)
        vm.grid = 16

        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)

        let h = Int(host.bounds.height)
        let w = Int(host.bounds.width)
        let scale = max(1.0, Double(rep.pixelsWide) / Double(w))

        func brightness(_ c: NSColor?) -> Double {
            guard let c else { return 0 }
            let cc = c.usingColorSpace(.deviceRGB) ?? c
            return Double((cc.redComponent + cc.greenComponent + cc.blueComponent) / 3.0)
        }
        var diffs: [Double] = []
        let sampleRows = stride(from: max(2, h / 5), through: h - 2, by: max(8, h / 6))
        for y in sampleRows {
            var prevBrightness: Double = 0
            var edges: [Int] = []
            for x in 1..<w {
                let b = brightness(rep.colorAt(x: x, y: y))
                let db = abs(b - prevBrightness)
                if db > 0.08 { edges.append(x) }
                prevBrightness = b
            }
            let pixelDiffs = zip(edges, edges.dropFirst()).map { Double($1 - $0) / scale }
            let rowDiffs = pixelDiffs.filter { $0 > 6 && $0 < 120 }
            diffs.append(contentsOf: rowDiffs)
        }
        guard diffs.count > 5 else { throw XCTSkip("insufficient edges to measure grid spacing across sampled rows at zoom!=1") }
        let sorted = diffs.sorted()
        let median = sorted[sorted.count/2]
        let expected = Double(CGFloat(vm.grid) * vm.zoom)
        XCTAssertEqual(median, expected, accuracy: 2.0, "minor spacing off at zoom/translation: median=\(median) expected=\(expected)")
    }
}
