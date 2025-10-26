#if canImport(AppKit)
import XCTest
import SwiftUI

@testable import patchbay_app

@MainActor
final class SnapshotHelper: XCTestCase {
    func testRenderCanvasSnapshot() throws {
        let vm = EditorVM()
        vm.grid = 24
        vm.zoom = 1.0
        vm.nodes = [
            PBNode(id: "A", title: "A", x: 40, y: 40, w: 160, h: 100, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: "B", x: 260, y: 160, w: 180, h: 120, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        vm.edges = [ PBEdge(from: "A.out", to: "B.in") ]

        let view = EditorCanvas().environmentObject(vm)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let img = NSImage(size: host.bounds.size)
        img.addRepresentation(rep)
        // Optionally write to /tmp for manual review
        if let tiff = img.tiffRepresentation {
            let url = URL(fileURLWithPath: "/tmp/patchbay-snapshot.tiff")
            try? tiff.write(to: url)
        }
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        XCTAssertGreaterThan(rep.pixelsHigh, 0)
    }
}
#endif

