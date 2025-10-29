import XCTest
@testable import patchbay_app
import SwiftUI

@MainActor
final class StageMarginsStressTests: XCTestCase {
    func testMarginsChangeAffectsRender() throws {
        let vm = EditorVM()
        let state = AppState()
        let sid = "stageStress1"
        vm.nodes.append(PBNode(id: sid, title: "Stage Stress", x: 10, y: 10, w: 595, h: 842, ports: []))
        state.registerDashNode(id: sid, kind: .stageA4, props: ["title": "Stage Stress", "page": "A4", "margins": "18,18,18,18", "baseline": "12"])
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        // Snapshot with small margins
        guard let imgA = ReplayDiffUtil.snapshot(host) else { throw XCTSkip("No snapshot") }

        // Increase margins via Stage instrument
        guard let robot = MIDIRobot(destName: "Stage #\(sid)") else { throw XCTSkip("Stage dest not found") }
        robot.setProperties(["stage.margins.top": 72.0, "stage.margins.left": 72.0, "stage.margins.bottom": 72.0, "stage.margins.right": 72.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        guard let imgB = ReplayDiffUtil.snapshot(host) else { throw XCTSkip("No snapshot") }
        let diff = ReplayDiffUtil.diff(imgA, imgB)
        XCTAssertGreaterThan(diff.mse, 0.5) // coarse threshold; margins should move page rect noticeably
    }
}
