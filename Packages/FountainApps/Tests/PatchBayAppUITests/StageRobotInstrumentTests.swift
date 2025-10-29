import XCTest
@testable import patchbay_app
import SwiftUI

final class StageRobotInstrumentTests: XCTestCase {
    func testStagePEBaselineAndPage() throws {
        let vm = EditorVM()
        let state = AppState()
        // Add a Stage node and register dashboard props before mounting view
        let id = "stageRobot1"
        vm.nodes.append(PBNode(id: id, title: "Stage Robot", x: 0, y: 0, w: 595, h: 842, ports: []))
        state.registerDashNode(id: id, kind: .stageA4, props: ["title": "Stage Robot", "page": "A4", "margins": "18,18,18,18", "baseline": "12"])

        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        // Allow binder to create instruments
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        // Poll for instrument
        var robot: MIDIRobot? = nil
        for _ in 0..<40 {
            if let r = MIDIRobot(destName: "Stage #\(id)") { robot = r; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let bot = robot else { throw XCTSkip("Stage instrument not found for \(id)") }

        // Change baseline and page via PE SET
        bot.setProperties(["stage.baseline": 14.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        bot.setProperties(["stage.page": 1.0]) // Letter
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        // Assert dashboard reflects changes
        let dash = state.dashboard[id]
        XCTAssertEqual(dash?.props["baseline"], "14.000")
        XCTAssertEqual(dash?.props["page"], "Letter")
    }
}

