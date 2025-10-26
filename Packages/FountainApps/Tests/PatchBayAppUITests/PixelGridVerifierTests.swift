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

        let y = Int(host.bounds.height * 0.4)
        let w = Int(host.bounds.width)

        // Detect vertical grid lines by brightness gradient
        var prevBrightness: Double = 0
        func brightness(_ c: NSColor?) -> Double {
            guard let c else { return 0 }
            let cc = c.usingColorSpace(.deviceRGB) ?? c
            return Double((cc.redComponent + cc.greenComponent + cc.blueComponent) / 3.0)
        }
        var edges: [Int] = []
        for x in 1..<w {
            let b = brightness(rep.colorAt(x: x, y: y))
            let db = abs(b - prevBrightness)
            if db > 0.08 { // robust threshold for grid line transitions
                edges.append(x)
            }
            prevBrightness = b
        }
        // Compute spacing between successive edges; filter obvious outliers
        let diffs = zip(edges, edges.dropFirst()).map { $1 - $0 }.filter { $0 > 6 && $0 < 60 }
        guard diffs.count > 5 else { throw XCTSkip("insufficient edges to measure grid spacing") }
        let sorted = diffs.sorted()
        let median = Double(sorted[sorted.count/2])

        // Expected minor spacing in view pixels
        let expected = Double(CGFloat(vm.grid) * vm.zoom)
        XCTAssertEqual(median, expected, accuracy: 2.0, "minor grid spacing off: median=\(median) expected=\(expected)")
    }
}
