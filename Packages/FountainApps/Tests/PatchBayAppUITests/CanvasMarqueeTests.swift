import XCTest
@testable import patchbay_app
import SwiftUI
@testable import MetalViewKit

@MainActor
final class CanvasMarqueeTests: XCTestCase {
    func testMarqueeSelectionRespectsCanvasTranslation() throws {
        let vm = EditorVM()
        vm.translation = CGPoint(x: 120, y: 80)
        vm.zoom = 1.0
        let node = PBNode(id: "nodeA", title: "Node A", x: 0, y: 0, w: 180, h: 140, ports: [])
        vm.nodes = [node]

        let state = AppState()
        state.registerDashNode(id: node.id, kind: .stageA4, props: [
            "title": node.title ?? node.id,
            "page": "A4",
            "margins": "18,18,18,18",
            "baseline": "12"
        ])

        let host = NSHostingView(rootView: MetalCanvasHost()
            .environmentObject(vm)
            .environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)

        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let canvasView = findMetalCanvasView(in: host) else {
            XCTFail("MetalCanvasNSView not found")
            return
        }
        window.makeFirstResponder(canvasView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let startViewPoint = NSPoint(x: 10, y: 10)
        let endViewPoint = NSPoint(x: 360, y: 300)
        guard
            let downEvent = NSEvent.mouseEvent(with: .leftMouseDown,
                                               location: canvasView.convert(startViewPoint, to: nil as NSView?),
                                               modifierFlags: [],
                                               timestamp: 0,
                                               windowNumber: window.windowNumber,
                                               context: nil,
                                               eventNumber: 0,
                                               clickCount: 1,
                                               pressure: 0),
            let dragEvent = NSEvent.mouseEvent(with: .leftMouseDragged,
                                               location: canvasView.convert(endViewPoint, to: nil as NSView?),
                                               modifierFlags: [],
                                               timestamp: 0.05,
                                               windowNumber: window.windowNumber,
                                               context: nil,
                                               eventNumber: 0,
                                               clickCount: 0,
                                               pressure: 0),
            let upEvent = NSEvent.mouseEvent(with: .leftMouseUp,
                                             location: canvasView.convert(endViewPoint, to: nil as NSView?),
                                             modifierFlags: [],
                                             timestamp: 0.1,
                                             windowNumber: window.windowNumber,
                                             context: nil,
                                             eventNumber: 0,
                                             clickCount: 0,
                                             pressure: 0)
        else {
            XCTFail("Unable to synthesise mouse events")
            return
        }

        canvasView.mouseDown(with: downEvent)
        canvasView.mouseDragged(with: dragEvent)
        canvasView.mouseUp(with: upEvent)
        XCTAssertEqual(vm.selected, ["nodeA"])
    }
}

@MainActor
private func findMetalCanvasView(in view: NSView) -> MetalCanvasNSView? {
    if let canvas = view as? MetalCanvasNSView { return canvas }
    for sub in view.subviews {
        if let hit = findMetalCanvasView(in: sub) { return hit }
    }
    return nil
}
