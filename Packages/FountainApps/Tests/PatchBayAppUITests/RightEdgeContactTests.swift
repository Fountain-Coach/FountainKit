import XCTest
@testable import patchbay_app
import SwiftUI

@MainActor
final class RightEdgeContactTests: XCTestCase {
    func testRightEdgeContactAndVisibleColumns_DefaultZoom() throws {
        let vm = EditorVM(); vm.zoom = 1.0; vm.translation = .zero; vm.grid = 24
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 850, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        defer { win.orderOut(nil) }

        let exp = expectation(description: "grid.contact")
        var rightIndex: Int = -1
        var rightX: Double = -1
        var columns: Int = -1
        let obs = NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            guard (note.userInfo?["type"] as? String) == "grid.contact" else { return }
            rightIndex = note.userInfo?["contact.grid.right.index"] as? Int ?? -1
            rightX = note.userInfo?["contact.grid.right.view.x"] as? Double ?? -1
            columns = note.userInfo?["visible.grid.columns"] as? Int ?? -1
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(obs) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        wait(for: [exp], timeout: 1.5)

        // For width=850, step=24 -> floor(850/24)=35, rightX=840, columns=36 (including 0)
        XCTAssertEqual(rightIndex, 35)
        XCTAssertEqual(rightX, 840, accuracy: 1.0)
        XCTAssertEqual(columns, 36)
    }

    func testRightEdgeContactAndVisibleColumns_Zoomed() throws {
        let vm = EditorVM(); vm.zoom = 1.25; vm.translation = .zero; vm.grid = 24
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        defer { win.orderOut(nil) }

        let exp = expectation(description: "grid.contact")
        var rightIndex: Int = -1
        var rightX: Double = -1
        var columns: Int = -1
        let obs = NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            guard (note.userInfo?["type"] as? String) == "grid.contact" else { return }
            rightIndex = note.userInfo?["contact.grid.right.index"] as? Int ?? -1
            rightX = note.userInfo?["contact.grid.right.view.x"] as? Double ?? -1
            columns = note.userInfo?["visible.grid.columns"] as? Int ?? -1
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(obs) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        wait(for: [exp], timeout: 1.5)

        // For width=800, step=24*1.25=30 -> floor(800/30)=26, rightX=780, columns=27
        XCTAssertEqual(rightIndex, 26)
        XCTAssertEqual(rightX, 780, accuracy: 1.0)
        XCTAssertEqual(columns, 27)
    }
}

