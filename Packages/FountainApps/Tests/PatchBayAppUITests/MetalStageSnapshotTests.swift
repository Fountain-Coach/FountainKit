#if canImport(AppKit)
import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class MetalStageSnapshotTests: XCTestCase {
    private func artifactsDir() -> URL {
        let root = URL(fileURLWithPath: ".fountain/artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testMetalStageRendersOrWrites() throws {
        let bundle = Bundle.module
        guard let baselineURL = bundle.url(forResource: "metal-stage-basic", withExtension: "tiff") else {
            let vm = EditorVM()
            vm.grid = 24
            vm.zoom = 1.0
            // Place a stage-sized node; actual rendering pulls stage from dashboard
            let s = PBNode(id: "Stage1", title: "The Stage", x: 40, y: 40, w: 420, h: 594, ports: [])
            vm.nodes = [s]
            let state = AppState()
            state.dashboard["Stage1"] = DashNode(id: "Stage1", kind: .stageA4, props: ["title":"The Stage", "page":"A4", "margins":"18,18,18,18", "baseline":"12"])
            let view = MetalCanvasHost().environmentObject(vm).environmentObject(state)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: host.bounds.size)
            img.addRepresentation(rep)
            let out = artifactsDir().appendingPathComponent("patchbay-metal-stage-basic.tiff")
            try? img.tiffRepresentation?.write(to: out)
            throw XCTSkip("Baseline not found. Candidate written to \(out.path)")
        }
        let vm = EditorVM()
        vm.grid = 24
        vm.zoom = 1.0
        let s = PBNode(id: "Stage1", title: "The Stage", x: 40, y: 40, w: 420, h: 594, ports: [])
        vm.nodes = [s]
        let state = AppState()
        state.dashboard["Stage1"] = DashNode(id: "Stage1", kind: .stageA4, props: ["title":"The Stage", "page":"A4", "margins":"18,18,18,18", "baseline":"12"])
        let view = MetalCanvasHost().environmentObject(vm).environmentObject(state)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard let actual = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep"); return }
        host.cacheDisplay(in: host.bounds, to: actual)
        let baselineData = try Data(contentsOf: baselineURL)
        let baseline = NSBitmapImageRep(data: baselineData)!
        let (diff, _) = SnapshotDiffTests.rmseDiffAndHeatmap(a: baseline, b: actual)
        XCTAssertLessThan(diff, 10.0, "Metal Stage snapshot RMSE too large: \(diff)")
    }
}
#endif
