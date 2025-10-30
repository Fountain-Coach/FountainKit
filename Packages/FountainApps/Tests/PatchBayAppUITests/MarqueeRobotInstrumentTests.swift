import XCTest
@testable import patchbay_app
import SwiftUI
import MetalViewKit

@MainActor
final class MarqueeRobotInstrumentTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        setenv("PATCHBAY_MIDI_TRANSPORT", "loopback", 1)
        MetalInstrument.setTransportOverride(LoopbackMetalInstrumentTransport.shared)
    }

    override func tearDownWithError() throws {
        MetalInstrument.setTransportOverride(nil)
        LoopbackMetalInstrumentTransport.shared.reset()
        try super.tearDownWithError()
    }

    func testMarqueeSelectsStageViaMIDI() throws {
        let vm = EditorVM()
        vm.translation = CGPoint(x: 96, y: 64)
        vm.zoom = 1.0
        let nodeId = "stageMarquee"
        vm.nodes.append(PBNode(id: nodeId, title: "Stage", x: 0, y: 0, w: 595, h: 842, ports: []))

        let state = AppState()
        state.registerDashNode(id: nodeId, kind: .stageA4, props: [
            "title": "Stage",
            "page": "A4",
            "margins": "18,18,18,18",
            "baseline": "12"
        ])

        let host = NSHostingView(rootView: MetalCanvasHost()
            .environmentObject(vm)
            .environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "PatchBay Canvas", timeout: 3.0) != nil else {
            XCTFail("Canvas instrument missing")
            return
        }
        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "Stage #\(nodeId)", timeout: 3.0) != nil else {
            XCTFail("Stage instrument missing")
            return
        }
        guard LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "Marquee Tool", timeout: 3.0) != nil else {
            XCTFail("Marquee instrument missing")
            return
        }
        guard let marqueeBot = MIDIRobot(destName: "Marquee Tool") else {
            XCTFail("Unable to attach marquee robot")
            return
        }

        var receivedOps: [String] = []
        var observedEnd = false
        let obs = NotificationCenter.default.addObserver(forName: .MetalCanvasMarqueeCommand, object: nil, queue: .main) { note in
            let op = note.userInfo?["op"] as? String
            MainActor.assumeIsolated {
                if let op {
                    receivedOps.append(op)
                    if op == "end" { observedEnd = true }
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(obs) }
        var marqueeEndSelected: [String]? = nil
        let activityObserver = NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            let info = note.userInfo
            let type = info?["type"] as? String
            let selected = info?["selected"] as? [String]
            MainActor.assumeIsolated {
                guard let type else { return }
                if type == "marquee.end" {
                    marqueeEndSelected = selected
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(activityObserver) }

        let origin = CGPoint(x: -60, y: -60)
        let current = CGPoint(x: 620, y: 880)

        marqueeBot.marqueeBegin(docX: Double(origin.x), docY: Double(origin.y))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        marqueeBot.marqueeUpdate(docX: Double(current.x), docY: Double(current.y))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        marqueeBot.marqueeEnd(docX: Double(current.x), docY: Double(current.y))
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        XCTAssertEqual(receivedOps, ["begin", "update", "end"])
        XCTAssertTrue(observedEnd)
        XCTAssertEqual(marqueeEndSelected, [nodeId])
        XCTAssertEqual(vm.selected, [nodeId])
    }
}
