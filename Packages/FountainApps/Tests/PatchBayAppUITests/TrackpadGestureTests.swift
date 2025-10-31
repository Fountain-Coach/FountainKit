import XCTest
@testable import patchbay_app
import SwiftUI
@testable import MetalViewKit
import CoreGraphics

@MainActor
final class TrackpadGestureTests: XCTestCase {
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
