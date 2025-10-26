import AppKit
import SwiftUI
@testable import patchbay_app

@main
struct PatchBaySnapshots {
    static func main() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "Packages/FountainApps/Tests/PatchBayAppUITests/Baselines", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        Task { @MainActor in
            do {
                // initial-open 1440x900
                let vm = EditorVM()
                let content = ContentView(state: AppState()).environmentObject(vm)
                let host = NSHostingView(rootView: content)
                host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 50_000_000)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let img = NSImage(size: host.bounds.size)
                    img.addRepresentation(rep)
                    let url = root.appendingPathComponent("initial-open.tiff")
                    try img.tiffRepresentation?.write(to: url)
                    fputs("wrote \(url.path)\n", stderr)
                }

                // basic-canvas 640x480
                let vm2 = EditorVM(); vm2.grid = 24; vm2.zoom = 1.0
                vm2.nodes = [
                    PBNode(id: "A", title: "A", x: 60, y: 60, w: 200, h: 120, ports: [.init(id: "out", side: .right, dir: .output)]),
                    PBNode(id: "B", title: "B", x: 360, y: 180, w: 220, h: 140, ports: [.init(id: "in", side: .left, dir: .input)])
                ]
                vm2.edges = [ PBEdge(from: "A.out", to: "B.in") ]
                let canvasHost = NSHostingView(rootView: EditorCanvas().environmentObject(vm2))
                canvasHost.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
                canvasHost.layoutSubtreeIfNeeded()
                if let rep2 = canvasHost.bitmapImageRepForCachingDisplay(in: canvasHost.bounds) {
                    canvasHost.cacheDisplay(in: canvasHost.bounds, to: rep2)
                    let img2 = NSImage(size: canvasHost.bounds.size)
                    img2.addRepresentation(rep2)
                    let url2 = root.appendingPathComponent("basic-canvas.tiff")
                    try img2.tiffRepresentation?.write(to: url2)
                    fputs("wrote \(url2.path)\n", stderr)
                }
                exit(0)
            } catch {
                fputs("error: \(error)\n", stderr)
                exit(2)
            }
        }
        dispatchMain()
    }
}
