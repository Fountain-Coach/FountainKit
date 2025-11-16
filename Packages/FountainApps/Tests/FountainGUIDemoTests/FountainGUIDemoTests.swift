import XCTest
import AppKit
@testable import fountain_gui_demo_app
import FountainGUIKit

@MainActor
final class FountainGUIDemoTests: XCTestCase {
    private func makeDemo() -> (DemoSurfaceView, DemoInstrumentTarget, FGKNode) {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let properties: [FGKPropertyDescriptor] = [
            .init(name: "canvas.zoom", kind: .float(min: 0.2, max: 5.0, default: 1.0)),
            .init(name: "canvas.translation.x", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),
            .init(name: "canvas.translation.y", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),
            .init(name: "canvas.rotation", kind: .float(min: -Double.pi * 2, max: Double.pi * 2, default: 0.0))
        ]
        let node = FGKNode(
            instrumentId: "fountain.gui.demo.surface",
            frame: frame,
            properties: properties,
            target: nil
        )
        let view = DemoSurfaceView(frame: frame, rootNode: node)
        let target = DemoInstrumentTarget(view: view, node: node)
        node.target = target
        return (view, target, node)
    }

    func testScrollPansCanvas() {
        let (view, target, _) = makeDemo()
        XCTAssertEqual(view.state.translation.x, 0)
        XCTAssertEqual(view.state.translation.y, 0)

        let scroll = FGKScrollEvent(
            locationInView: NSPoint(x: 100, y: 100),
            deltaX: 10,
            deltaY: -5,
            modifiers: []
        )
        _ = target.handle(event: .scroll(scroll))

        XCTAssertEqual(view.state.translation.x, 10, accuracy: 0.001)
        XCTAssertEqual(view.state.translation.y, -5, accuracy: 0.001)
    }

    func testMagnifyZoomsCanvas() {
        let (view, target, _) = makeDemo()
        XCTAssertEqual(view.state.zoom, 1.0, accuracy: 0.0001)

        let magnify = FGKMagnifyEvent(
            locationInView: NSPoint(x: 200, y: 200),
            magnification: 0.5,
            modifiers: []
        )
        _ = target.handle(event: .magnify(magnify))

        XCTAssertGreaterThan(view.state.zoom, 1.0)
    }

    func testRotateAdjustsRotation() {
        let (view, target, _) = makeDemo()
        XCTAssertEqual(view.state.rotation, 0.0, accuracy: 0.0001)

        let rotate = FGKRotateEvent(
            locationInView: NSPoint(x: 200, y: 200),
            rotation: 45,
            modifiers: []
        )
        _ = target.handle(event: .rotate(rotate))

        XCTAssertNotEqual(view.state.rotation, 0.0)
    }
}

@MainActor
final class FountainGUIDemoSnapshotTests: XCTestCase {
    private struct Scenario {
        let name: String
        let configure: (DemoSurfaceView, DemoInstrumentTarget) -> Void
    }

    private func baselineDir() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Packages/FountainApps/Tests/FountainGUIDemoTests/Baselines", isDirectory: true)
    }

    private func artifactsDir() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".fountain/artifacts/pbvrt/fountain-gui-demo", isDirectory: true)
    }

    private func makeDemo() -> (DemoSurfaceView, DemoInstrumentTarget) {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let properties: [FGKPropertyDescriptor] = [
            .init(name: "canvas.zoom", kind: .float(min: 0.2, max: 5.0, default: 1.0)),
            .init(name: "canvas.translation.x", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),
            .init(name: "canvas.translation.y", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),
            .init(name: "canvas.rotation", kind: .float(min: -Double.pi * 2, max: Double.pi * 2, default: 0.0))
        ]
        let node = FGKNode(
            instrumentId: "fountain.gui.demo.surface",
            frame: frame,
            properties: properties,
            target: nil
        )
        let view = DemoSurfaceView(frame: frame, rootNode: node)
        let target = DemoInstrumentTarget(view: view, node: node)
        node.target = target
        return (view, target)
    }

    func testSnapshots_canvasStates() throws {
        let scenarios: [Scenario] = [
            Scenario(name: "base") { _, _ in },
            Scenario(name: "zoomed") { _, target in
                let magnify = FGKMagnifyEvent(locationInView: NSPoint(x: 320, y: 200), magnification: 0.5, modifiers: [])
                _ = target.handle(event: .magnify(magnify))
            },
            Scenario(name: "panned") { _, target in
                let scroll = FGKScrollEvent(locationInView: NSPoint(x: 320, y: 200), deltaX: 40, deltaY: -20, modifiers: [])
                _ = target.handle(event: .scroll(scroll))
            },
            Scenario(name: "rotated") { _, target in
                let rotate = FGKRotateEvent(locationInView: NSPoint(x: 320, y: 200), rotation: 45, modifiers: [])
                _ = target.handle(event: .rotate(rotate))
            }
        ]

        let size = CGSize(width: 640, height: 400)
        let update = (ProcessInfo.processInfo.environment["UPDATE_BASELINES"] == "1")

        for scenario in scenarios {
            autoreleasepool {
                let (view, target) = makeDemo()
                scenario.configure(view, target)
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                let img = DemoSnapshotUtils.renderImage(of: view, size: size)
                let baselineURL = baselineDir()
                    .appendingPathComponent(scenario.name, isDirectory: true)
                    .appendingPathComponent("canvas.png")

                if update {
                    try? DemoSnapshotUtils.writePNG(img, to: baselineURL)
                } else if let baseline = DemoSnapshotUtils.loadPNG(baselineURL) {
                    if let diff = DemoSnapshotUtils.diffRMSE(img, baseline) {
                        if diff.rmse > 0.01 {
                            let artifacts = artifactsDir()
                                .appendingPathComponent(scenario.name)
                                .appendingPathComponent("\(Int(Date().timeIntervalSince1970))")
                            try? DemoSnapshotUtils.writePNG(img, to: artifacts.appendingPathComponent("candidate.png"))
                            try? DemoSnapshotUtils.writePNG(baseline, to: artifacts.appendingPathComponent("baseline.png"))
                            try? DemoSnapshotUtils.writePNG(diff.heatmap, to: artifacts.appendingPathComponent("heatmap.png"))
                            XCTFail("Snapshot drift (\(scenario.name)) rmse=\(diff.rmse). Artifacts at \(artifacts.path)")
                        }
                    }
                } else {
                    try? DemoSnapshotUtils.writePNG(img, to: baselineURL)
                    XCTFail("Baseline missing for \(scenario.name); wrote candidate to \(baselineURL.path)")
                }
            }
        }
    }
}
