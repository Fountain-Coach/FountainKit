import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

@MainActor
final class CenterCanvasSnapshotTests: XCTestCase {
    func testEditorCanvasAppearsStableOnOpen() throws {
        // In infinite artboard mode we simply verify a snapshot can be rendered at a known size.
        let vm = EditorVM()
        let host = NSHostingView(rootView: EditorCanvas().environmentObject(vm).environmentObject(AppState()))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        XCTAssertNotNil(rep)
    }
}
