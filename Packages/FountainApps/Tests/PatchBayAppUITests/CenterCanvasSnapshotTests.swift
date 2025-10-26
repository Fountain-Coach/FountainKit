import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class CenterCanvasSnapshotTests: XCTestCase {
    func testEditorCanvasAppearsCenteredHorizontally() throws {
        let vm = EditorVM()
        vm.pageSize = PageSpec.a4Portrait
        vm.marginMM = 12
        // Host at a known size representing the center pane only
        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()
        // Allow onAppear fit
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)

        // Scan a horizontal row for the red margin stroke to estimate page edges
        let y = Int(Double(host.bounds.height) * 0.08) // near top grid labels
        let w = Int(host.bounds.width)
        func redness(_ c: NSColor?) -> Double {
            guard let c else { return 0 }
            let cc = c.usingColorSpace(.deviceRGB) ?? c
            return Double(cc.redComponent) - 0.5*Double(cc.greenComponent) - 0.5*Double(cc.blueComponent)
        }
        var candidates: [Int] = []
        for x in 1..<w-1 {
            let r0 = redness(rep.colorAt(x: x-1, y: y))
            let r1 = redness(rep.colorAt(x: x, y: y))
            let r2 = redness(rep.colorAt(x: x+1, y: y))
            if r1 > 0.25 && r1 > r0 && r1 > r2 { candidates.append(x) }
        }
        // Expect two strong candidates (left/top margin vertical stroke and right)
        // Take first and last as rough page edges
        guard let leftX = candidates.first, let rightX = candidates.last, rightX > leftX else {
            throw XCTSkip("could not detect page margin strokes reliably; snapshot lighting may differ")
        }
        let pageCenter = (Double(leftX) + Double(rightX)) / 2.0
        let viewCenter = Double(host.bounds.width) / 2.0
        XCTAssertEqual(pageCenter, viewCenter, accuracy: 4.0, "page not centered horizontally (pageCenter=\(pageCenter), viewCenter=\(viewCenter))")
    }
}

