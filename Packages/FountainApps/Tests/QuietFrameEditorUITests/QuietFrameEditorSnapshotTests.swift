import XCTest
import SwiftUI
import AppKit
@testable import quietframe_sonify_app

@MainActor
final class QuietFrameEditorSnapshotTests: XCTestCase {
    struct Size { let w: CGFloat; let h: CGFloat; let name: String }
    let sizes = [Size(w: 1440, h: 900, name: "1440x900"), Size(w: 1280, h: 800, name: "1280x800")]

    func testSnapshots_editorSurface() throws {
        for s in sizes {
            autoreleasepool {
                let hosting = NSHostingView(rootView: FountainEditorSurface(frameSize: CGSize(width: 1024, height: 1536)))
                hosting.frame = NSRect(x: 0, y: 0, width: s.w, height: s.h)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let img = SnapshotUtils.renderImage(of: hosting, size: CGSize(width: s.w, height: s.h))
                let baselineURL = baselineDir().appendingPathComponent("\(s.name)/quietframe-editor.png")
                let update = (ProcessInfo.processInfo.environment["UPDATE_BASELINES"] == "1")
                if update {
                    try? SnapshotUtils.writePNG(img, to: baselineURL)
                } else if let baseline = SnapshotUtils.loadPNG(baselineURL) {
                    if let diff = SnapshotUtils.diffRMSE(img, baseline) {
                        if diff.rmse > 0.01 {
                            let artifacts = artifactsDir().appendingPathComponent("qf-editor/\(Int(Date().timeIntervalSince1970))/\(s.name)")
                            try? SnapshotUtils.writePNG(img, to: artifacts.appendingPathComponent("candidate.png"))
                            try? SnapshotUtils.writePNG(baseline, to: artifacts.appendingPathComponent("baseline.png"))
                            try? SnapshotUtils.writePNG(diff.heatmap, to: artifacts.appendingPathComponent("heatmap.png"))
                            XCTFail("Snapshot drift (\(s.name)) rmse=\(diff.rmse). Artifacts at \(artifacts.path)")
                        }
                    }
                } else {
                    try? SnapshotUtils.writePNG(img, to: baselineURL)
                    XCTFail("Baseline missing for \(s.name); wrote candidate to \(baselineURL.path)")
                }
            }
        }
    }

    private func baselineDir() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Packages/FountainApps/Tests/QuietFrameEditorUITests/Baselines", isDirectory: true)
    }
    private func artifactsDir() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".fountain/artifacts/pbvrt", isDirectory: true)
    }
}

