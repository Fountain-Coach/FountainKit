import Foundation
import AppKit
import SwiftUI

@main
struct EditorSnapshotsMain {
    static func main() throws {
        // Ensure AppKit is initialized for headless rendering
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let args = CommandLine.arguments.dropFirst()
        let update = args.contains("--update")
        let sizes = [(1440,900,"1440x900"),(1280,800,"1280x800")]
        // Deterministic seeded text; keep in sync with tests
        let seed = ProcessInfo.processInfo.environment["EDITOR_SEED_TEXT"] ?? "# Act 1\n\n## Scene One\n\nINT. SCENE ONE — DAY\n\nText."
        var failures = 0
        for (w,h,name) in sizes {
            var img: NSImage!
            DispatchQueue.main.sync {
                let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.titled], backing: .buffered, defer: false)
                let hosting = NSHostingView(rootView: EditorSnapshotView(seedText: seed))
                hosting.frame = win.contentView!.bounds
                hosting.autoresizingMask = [.width,.height]
                win.contentView!.addSubview(hosting)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                img = SnapshotUtils.renderImage(of: hosting, size: CGSize(width: w, height: h))
                win.close()
            }
            let baseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Packages/FountainApps/Tests/EditorAppUITests/Baselines/\(name)", isDirectory: true)
            let baselineURL = baseDir.appendingPathComponent("editor.png")
            if update || !FileManager.default.fileExists(atPath: baselineURL.path) {
                try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
                try SnapshotUtils.writePNG(img, to: baselineURL)
                print("[editor-snapshots] wrote baseline \(baselineURL.path)")
            } else {
                if let baseline = SnapshotUtils.loadPNG(baselineURL), let diff = SnapshotUtils.diffRMSE(img, baseline) {
                    if diff.rmse > 0.01 {
                        failures += 1
                        let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".fountain/artifacts/pbvrt/editor/\(Int(Date().timeIntervalSince1970))/\(name)", isDirectory: true)
                        try? SnapshotUtils.writePNG(img, to: out.appendingPathComponent("candidate.png"))
                        try? SnapshotUtils.writePNG(baseline, to: out.appendingPathComponent("baseline.png"))
                        try? SnapshotUtils.writePNG(diff.heatmap, to: out.appendingPathComponent("heatmap.png"))
                        print("[editor-snapshots] drift on \(name) rmse=\(diff.rmse) artifacts=\(out.path)")
                    } else {
                        print("[editor-snapshots] ok \(name) rmse=\(diff.rmse)")
                    }
                } else {
                    print("[editor-snapshots] failed to load baseline \(baselineURL.path)")
                    failures += 1
                }
            }
        }
        if failures > 0 { exit(1) }
    }
}
