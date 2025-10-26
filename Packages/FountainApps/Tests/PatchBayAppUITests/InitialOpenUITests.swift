import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class InitialOpenUITests: XCTestCase {
    func testEditorCanvasFitsA4OnAppear() async throws {
        let vm = EditorVM()
        vm.pageSize = PageSpec.a4Portrait
        vm.zoom = 0.5
        vm.translation = .zero

        // Host the canvas at a deterministic view size
        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
        host.layoutSubtreeIfNeeded()

        // Give SwiftUI a short moment to deliver onAppear/GeometryReader updates
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let expectedZ = EditorVM.computeFitZoom(viewSize: host.bounds.size, contentBounds: CGRect(origin: .zero, size: vm.pageSize))
        let expectedT = EditorVM.computeCenterTranslation(viewSize: host.bounds.size, contentBounds: CGRect(origin: .zero, size: vm.pageSize), zoom: expectedZ)

        XCTAssertEqual(vm.zoom, expectedZ, accuracy: 0.01, "zoom should fit page on appear")
        XCTAssertEqual(vm.translation.x, expectedT.x, accuracy: 1.0, "translation.x centers page")
        XCTAssertEqual(vm.translation.y, expectedT.y, accuracy: 1.0, "translation.y centers page")
    }
}
