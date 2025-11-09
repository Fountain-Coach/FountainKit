import XCTest
import SwiftUI
import AppKit
@testable import quietframe_editor_app

@MainActor
final class EditorSnapshotTests: XCTestCase {
    struct Size { let w: CGFloat; let h: CGFloat; let name: String }
    let sizes = [Size(w: 1440, h: 900, name: "1440x900"), Size(w: 1280, h: 800, name: "1280x800")]

    func testSnapshots_editorLanding() throws {
        for s in sizes {
            autoreleasepool {
                // Seed deterministic text to avoid server dependency
                setenv("EDITOR_SEED_TEXT", "# Act 1\n\n## Scene One\n\nINT. SCENE ONE — DAY\n\nText.", 1)
                let hosting = NSHostingView(rootView: EditorLandingView())
                hosting.frame = NSRect(x: 0, y: 0, width: s.w, height: s.h)
                // Allow initial load task to run a tick
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))

                let img = SnapshotUtils.renderImage(of: hosting, size: CGSize(width: s.w, height: s.h))
                let baselineURL = baselineDir().appendingPathComponent("\(s.name)/editor.png")
                let update = (ProcessInfo.processInfo.environment["UPDATE_BASELINES"] == "1")
                if update {
                    try? SnapshotUtils.writePNG(img, to: baselineURL)
                    // In update mode, do not fail; treat as success
                } else if let baseline = SnapshotUtils.loadPNG(baselineURL) {
                    if let diff = SnapshotUtils.diffRMSE(img, baseline) {
                        if diff.rmse > 0.01 {
                            let artifacts = artifactsDir().appendingPathComponent("editor/\(Int(Date().timeIntervalSince1970))")
                            try? SnapshotUtils.writePNG(img, to: artifacts.appendingPathComponent("candidate.png"))
                            try? SnapshotUtils.writePNG(baseline, to: artifacts.appendingPathComponent("baseline.png"))
                            try? SnapshotUtils.writePNG(diff.heatmap, to: artifacts.appendingPathComponent("heatmap.png"))
                            XCTFail("Snapshot drift (\(s.name)) rmse=\(diff.rmse). Artifacts at \(artifacts.path)")
                        }
                    }
                } else if !update {
                    // First run: write candidate and fail to force review/commit
                    let out = baselineURL
                    try? SnapshotUtils.writePNG(img, to: out)
                    XCTFail("Baseline missing for \(s.name); wrote candidate to \(out.path)")
                }
            }
        }
    }

    private func baselineDir() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Packages/FountainApps/Tests/EditorAppUITests/Baselines", isDirectory: true)
    }

    private func artifactsDir() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".fountain/artifacts/pbvrt", isDirectory: true)
    }
}
