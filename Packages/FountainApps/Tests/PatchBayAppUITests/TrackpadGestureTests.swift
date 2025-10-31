import XCTest
@testable import patchbay_app
import SwiftUI
@testable import MetalViewKit
import CoreGraphics

@MainActor
final class TrackpadGestureTests: XCTestCase {
    func testBlankDragPansCanvasFollowFinger() throws {
        let (win, host, vm, state) = makeHost(); defer { _ = host; _ = win; _ = state }
        vm.zoom = 1.0; vm.translation = .zero
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let canvasView = findMetalCanvasView(in: host) else { throw XCTSkip("canvas view not found") }
        win.makeFirstResponder(canvasView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        var lastTX: Double = 0, lastTY: Double = 0
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasTransformChanged"), object: nil, queue: .main) { note in
            let u = note.userInfo ?? [:]
            if let tx = u["tx"] as? Double { lastTX = tx }
            if let ty = u["ty"] as? Double { lastTY = ty }
        }
        let startView = NSPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
        let endView = NSPoint(x: startView.x + 120, y: startView.y + 80)
        guard
            let down = NSEvent.mouseEvent(with: .leftMouseDown,
                                          location: canvasView.convert(startView, to: nil as NSView?),
                                          modifierFlags: [], timestamp: 0,
                                          windowNumber: win.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 0),
            let drag = NSEvent.mouseEvent(with: .leftMouseDragged,
                                          location: canvasView.convert(endView, to: nil as NSView?),
                                          modifierFlags: [], timestamp: 0.05,
                                          windowNumber: win.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 0, pressure: 0),
            let up = NSEvent.mouseEvent(with: .leftMouseUp,
                                        location: canvasView.convert(endView, to: nil as NSView?),
                                        modifierFlags: [], timestamp: 0.1,
                                        windowNumber: win.windowNumber, context: nil,
                                        eventNumber: 0, clickCount: 0, pressure: 0)
        else { XCTFail("failed to synthesize mouse events"); return }
        canvasView.mouseDown(with: down)
        canvasView.mouseDragged(with: drag)
        canvasView.mouseUp(with: up)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        NotificationCenter.default.removeObserver(obs)
        XCTAssertEqual(lastTX, 120.0, accuracy: 2.0)
        XCTAssertEqual(lastTY, 80.0, accuracy: 2.0)
    }
    func testPanByRendererEmulatesScrollWheel() throws {
        let (win, host, _, _) = makeHost(); defer { _ = host; _ = win }
        var renderer: MetalCanvasRenderer? = nil
        let got = expectation(description: "renderer")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { note in
            renderer = (note.userInfo?["renderer"] as? MetalCanvasRenderer)
            if renderer != nil { got.fulfill() }
        }
        wait(for: [got], timeout: 2.0)
        NotificationCenter.default.removeObserver(obs)
        guard let r = renderer else { XCTFail("no renderer"); return }
        // reset
        r.applyUniform("zoom", value: 1.0)
        r.applyUniform("translation.x", value: 0)
        r.applyUniform("translation.y", value: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        // emulate scroll by calling the same pan code path as scrollWheel (view→doc via /zoom)
        let dxView: CGFloat = 120, dyView: CGFloat = 80
        let dxDoc = dxView / max(0.0001, r.currentZoom)
        let dyDoc = dyView / max(0.0001, r.currentZoom)
        r.panBy(docDX: dxDoc, docDY: dyDoc)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(Double(r.currentTranslation.x), Double(dxDoc), accuracy: 1.0)
        XCTAssertEqual(Double(r.currentTranslation.y), Double(dyDoc), accuracy: 1.0)
    }

    func testZoomAroundViaRendererEmulatesPinch() throws {
        // We drive the same code path magnify(with:) uses (renderer.zoomAround)
        let (win, host, _, _) = makeHost(); defer { _ = host; _ = win }
        var renderer: MetalCanvasRenderer? = nil
        let got = expectation(description: "renderer")
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name("MetalCanvasRendererReady"), object: nil, queue: .main) { note in
            renderer = (note.userInfo?["renderer"] as? MetalCanvasRenderer)
            if renderer != nil { got.fulfill() }
        }
        wait(for: [got], timeout: 2.0)
        NotificationCenter.default.removeObserver(obs)
        guard let r = renderer else { XCTFail("no renderer"); return }
        let anchor = CGPoint(x: 320, y: 240)
        let before = (z: r.currentZoom, t: r.currentTranslation)
        r.zoomAround(anchorView: anchor, magnification: 0.2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let after = (z: r.currentZoom, t: r.currentTranslation)
        var c = Canvas2D(zoom: before.z, translation: before.t)
        let doc = c.viewToDoc(anchor)
        c = Canvas2D(zoom: after.z, translation: after.t)
        let reproject = c.docToView(doc)
        XCTAssertLessThan(abs(reproject.x - anchor.x), 1.0)
        XCTAssertLessThan(abs(reproject.y - anchor.y), 1.0)
    }

    // Helpers
    private func makeHost() -> (NSWindow, NSHostingView<AnyView>, EditorVM, AppState) {
        let vm = EditorVM(); let state = AppState()
        let content = AnyView(MetalCanvasHost().environmentObject(vm).environmentObject(state))
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        return (win, host, vm, state)
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
