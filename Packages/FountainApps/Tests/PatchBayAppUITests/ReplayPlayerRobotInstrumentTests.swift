import XCTest
@testable import patchbay_app
import SwiftUI

@MainActor
final class ReplayPlayerRobotInstrumentTests: XCTestCase {
    func testReplayPEProperties() throws {
        let vm = EditorVM()
        let state = AppState()
        let id = "replayRobot1"
        vm.nodes.append(PBNode(id: id, title: "Replay Robot", x: 100, y: 100, w: 240, h: 160, ports: []))
        state.registerDashNode(id: id, kind: .replayPlayer, props: ["title": "Replay", "fps": "10", "playing": "0", "frame": "0"])

        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        var robot: MIDIRobot? = nil
        for _ in 0..<40 {
            if let r = MIDIRobot(destName: "Replay #\(id)") { robot = r; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let bot = robot else { throw XCTSkip("Replay instrument not found for \(id)") }

        bot.setProperties(["replay.play": 1.0, "replay.fps": 12.0, "replay.frame": 42.0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let dash = state.dashboard[id]
        XCTAssertEqual(dash?.props["playing"], "1")
        XCTAssertEqual(dash?.props["fps"], "12.000")
        XCTAssertEqual(dash?.props["frame"], "42")
    }
}
