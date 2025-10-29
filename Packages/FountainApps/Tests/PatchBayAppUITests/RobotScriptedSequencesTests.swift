import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class RobotScriptedSequencesTests: XCTestCase {
    // Scripted pan/zoom sequence using the MIDI Robot. On assertion failure, exports a replay movie from the latest log.
    func testRobotScriptedPanZoomScenario() async throws {
        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        host.layoutSubtreeIfNeeded()

        var lastZoom: CGFloat = 1.0
        var lastTx: CGFloat = 0
        var lastTy: CGFloat = 0
        let changeExp = expectation(description: "transform changed")
        changeExp.isInverted = false
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            let z = (u["zoom"] as? Double)
            let tx = (u["tx"] as? Double)
            let ty = (u["ty"] as? Double)
            MainActor.assumeIsolated {
                if let z { lastZoom = CGFloat(z) }
                if let tx { lastTx = CGFloat(tx) }
                if let ty { lastTy = CGFloat(ty) }
            }
        }
        // Warm up run loop
        try? await Task.sleep(nanoseconds: 200_000_000)

        guard let robot = MIDIRobot(destName: "PatchBay Canvas") else {
            throw XCTSkip("Robot could not attach to PatchBay Canvas destination")
        }

        // Reset to known state
        robot.setProperties(["translation.x": 0.0, "translation.y": 0.0, "zoom": 1.0])
        try? await Task.sleep(nanoseconds: 150_000_000)
        // Step 1: pan by (+120, -80) doc units (apply absolute via PE SET)
        var expectTx = lastTx + 120
        var expectTy = lastTy - 80
        robot.setProperties(["translation.x": Double(expectTx), "translation.y": Double(expectTy)])
        try? await Task.sleep(nanoseconds: 150_000_000)
        if abs(lastTx - expectTx) > 1.0 || abs(lastTy - expectTy) > 1.0 {
            await exportLatestReplayArtifact()
        }
        XCTAssertEqual(lastTx, expectTx, accuracy: 1.0)
        XCTAssertEqual(lastTy, expectTy, accuracy: 1.0)

        // Step 2: zoom to 1.5 (absolute)
        robot.setProperties(["zoom": 1.5])
        try? await Task.sleep(nanoseconds: 150_000_000)
        if abs(lastZoom - 1.5) > 0.02 { await exportLatestReplayArtifact() }
        XCTAssertEqual(lastZoom, 1.5, accuracy: 0.02)

        // Step 3: pan by (-60, +40) doc units
        expectTx = lastTx - 60
        expectTy = lastTy + 40
        robot.setProperties(["translation.x": Double(expectTx), "translation.y": Double(expectTy)])
        try? await Task.sleep(nanoseconds: 150_000_000)
        if abs(lastTx - expectTx) > 1.0 || abs(lastTy - expectTy) > 1.0 { await exportLatestReplayArtifact() }
        XCTAssertEqual(lastTx, expectTx, accuracy: 1.0)
        XCTAssertEqual(lastTy, expectTy, accuracy: 1.0)

        NotificationCenter.default.removeObserver(obs)
    }

    @MainActor
    private func exportLatestReplayArtifact() async {
        guard let log = latestLogURL() else { return }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let outRoot = cwd.appendingPathComponent(".fountain/artifacts/replay", isDirectory: true)
        try? fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
        let base = log.deletingPathExtension().lastPathComponent
        let outDir = outRoot.appendingPathComponent(base, isDirectory: true)
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let outURL = outDir.appendingPathComponent("\(base)-fail-\(stamp).mov")
        try? await ReplayMovieExporter.exportMovie(from: log, to: outURL, width: 1024, height: 768, fps: 10)
    }

    private func latestLogURL() -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent(".fountain/corpus/ump", isDirectory: true)
            if let items = try? fm.contentsOfDirectory(at: candidate, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]),
               let latest = items.filter({ $0.lastPathComponent.hasPrefix("stream-") && $0.pathExtension == "ndjson" }).sorted(by: { (a, b) in
                   let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                   let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                   return da > db
               }).first { return latest }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
