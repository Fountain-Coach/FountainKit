import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class InitialOpenUITests: XCTestCase {
    func testEditorCanvasInitialOpenResetsZoomAndCenter() async throws {
        let vm = EditorVM()
        vm.zoom = 0.5
        vm.translation = CGPoint(x: 123, y: -77)

        // Host the canvas at a deterministic view size
        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
        host.layoutSubtreeIfNeeded()

        // Give SwiftUI a short moment to deliver onAppear/GeometryReader updates
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Infinite artboard: expect zoom=1 and translation reset to zero.
        XCTAssertEqual(vm.zoom, 1.0, accuracy: 0.01)
        XCTAssertEqual(vm.translation.x, 0, accuracy: 0.5)
        XCTAssertEqual(vm.translation.y, 0, accuracy: 0.5)
    }
}
