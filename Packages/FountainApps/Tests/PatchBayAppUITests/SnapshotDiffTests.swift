#if canImport(AppKit)
import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class SnapshotDiffTests: XCTestCase {
    private func artifactsDir() -> URL {
        let root = URL(fileURLWithPath: ".fountain/artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testCanvasMatchesBaselineOrWrites() throws {
        let bundle = Bundle.module
        // Try to load baseline from resources
        guard let baselineURL = bundle.url(forResource: "basic-canvas", withExtension: "tiff") else {
            // Generate and write a candidate for approval
            let vm = EditorVM()
            vm.grid = 24
            vm.zoom = 1.0
            vm.nodes = [
                PBNode(id: "A", title: "A", x: 60, y: 60, w: 200, h: 120, ports: [.init(id: "out", side: .right, dir: .output)]),
                PBNode(id: "B", title: "B", x: 360, y: 180, w: 220, h: 140, ports: [.init(id: "in", side: .left, dir: .input)])
            ]
            vm.edges = [ PBEdge(from: "A.out", to: "B.in") ]
            let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: host.bounds.size)
            img.addRepresentation(rep)
            let out = artifactsDir().appendingPathComponent("patchbay-basic-canvas.tiff")
            try? img.tiffRepresentation?.write(to: out)
            throw XCTSkip("Baseline not found. Candidate written to \(out.path)")
        }
        // Create actual snapshot
        let vm = EditorVM()
        vm.grid = 24
        vm.zoom = 1.0
        vm.nodes = [
            PBNode(id: "A", title: "A", x: 60, y: 60, w: 200, h: 120, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: "B", x: 360, y: 180, w: 220, h: 140, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        vm.edges = [ PBEdge(from: "A.out", to: "B.in") ]
        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let actual = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep"); return }
        host.cacheDisplay(in: host.bounds, to: actual)
        let baselineData = try Data(contentsOf: baselineURL)
        let baseline = NSBitmapImageRep(data: baselineData)!
        let (diff, heatmap) = Self.rmseDiffAndHeatmap(a: baseline, b: actual)
        if diff > 2.0, let img = heatmap, let data = img.tiffRepresentation {
            let out = artifactsDir().appendingPathComponent("patchbay-snapshot-heatmap.tiff")
            try? data.write(to: out)
        }
        XCTAssertLessThan(diff, 2.0, "Snapshot RMSE too large: \(diff)")
    }

    func testContentViewInitialOpenSnapshotOrWrites() throws {
        let bundle = Bundle.module
        guard let baselineURL = bundle.url(forResource: "initial-open", withExtension: "tiff") else {
            // Build a snapshot candidate
            let state = AppState(api: AppViewTests.MockAPI())
            let vm = EditorVM()
            let view = ContentView(state: state).environmentObject(vm)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
            host.layoutSubtreeIfNeeded()
            // Let async loads settle a moment
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: host.bounds.size)
            img.addRepresentation(rep)
            let out = artifactsDir().appendingPathComponent("patchbay-initial-open.tiff")
            try? img.tiffRepresentation?.write(to: out)
            throw XCTSkip("Baseline not found. Candidate written to \(out.path)")
        }
        let state = AppState(api: AppViewTests.MockAPI())
        let vm = EditorVM()
        let view = ContentView(state: state).environmentObject(vm)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard let actual = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep"); return }
        host.cacheDisplay(in: host.bounds, to: actual)
        let baselineData = try Data(contentsOf: baselineURL)
        let baseline = NSBitmapImageRep(data: baselineData)!
        let (diff, heatmap) = Self.rmseDiffAndHeatmap(a: baseline, b: actual)
        if diff > 5.0, let img = heatmap, let data = img.tiffRepresentation {
            let out = artifactsDir().appendingPathComponent("patchbay-initial-open-heatmap.tiff")
            try? data.write(to: out)
        }
        XCTAssertLessThan(diff, 5.0, "Initial open snapshot RMSE too large: \(diff)")
    }

    func testInitialOpen1280x800PortraitOrWrites() throws {
        let bundle = Bundle.module
        guard let baselineURL = bundle.url(forResource: "initial-open-1280x800-portrait", withExtension: "tiff") else {
            let vm = EditorVM()
            let view = ContentView(state: AppState()).environmentObject(vm)
            let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: host.bounds.size); img.addRepresentation(rep)
            let out = artifactsDir().appendingPathComponent("patchbay-initial-open-1280x800-portrait.tiff")
            try? img.tiffRepresentation?.write(to: out)
            throw XCTSkip("Baseline not found. Wrote candidate: \(out.path)")
        }
        let vm = EditorVM()
        let view = ContentView(state: AppState()).environmentObject(vm)
        let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        host.layoutSubtreeIfNeeded()
        guard let actual = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep"); return }
        host.cacheDisplay(in: host.bounds, to: actual)
        let baseline = NSBitmapImageRep(data: try Data(contentsOf: baselineURL))!
        let (diff, heatmap) = Self.rmseDiffAndHeatmap(a: baseline, b: actual)
        if diff > 5.0, let img = heatmap, let data = img.tiffRepresentation {
            try? data.write(to: artifactsDir().appendingPathComponent("patchbay-initial-open-1280x800-portrait-heatmap.tiff"))
        }
        XCTAssertLessThan(diff, 5.0)
    }

    static func rmseDiffAndHeatmap(a: NSBitmapImageRep, b: NSBitmapImageRep) -> (Double, NSImage?) {
        let w = min(a.pixelsWide, b.pixelsWide)
        let h = min(a.pixelsHigh, b.pixelsHigh)
        var sum: Double = 0
        var count: Double = 0
        let bytesPerPixel = 4
        var heat = [UInt8](repeating: 0, count: w*h*bytesPerPixel)
        for y in 0..<h {
            for x in 0..<w {
                var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
                var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
                a.colorAt(x: x, y: y)?.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
                b.colorAt(x: x, y: y)?.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
                let dr = Double(ar - br), dg = Double(ag - bg), db = Double(ab - bb)
                sum += dr*dr + dg*dg + db*db
                count += 3
                let mag = min(1.0, sqrt(dr*dr + dg*dg + db*db))
                let r = UInt8(min(255.0, mag*255.0))
                let i = (y*w + x)*bytesPerPixel
                heat[i+0] = r; heat[i+1] = 0; heat[i+2] = 0; heat[i+3] = 255
            }
        }
        let rmse = sqrt(sum / max(1, count)) * 255.0
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w*bytesPerPixel, bitsPerPixel: bytesPerPixel*8)!
        heat.withUnsafeBytes { raw in
            rep.bitmapData?.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: w*h*bytesPerPixel)
        }
        let img = NSImage(size: NSSize(width: w, height: h)); img.addRepresentation(rep)
        return (rmse, img)
    }
}
#endif
