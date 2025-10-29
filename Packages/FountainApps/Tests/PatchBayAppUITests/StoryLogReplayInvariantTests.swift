import XCTest
@testable import patchbay_app
import MetalViewKit

final class StoryLogReplayInvariantTests: XCTestCase {
    // Optional, only runs if a recent log exists locally.
    func testReplayPanZoomInvariantsFromLatestLogIfPresent() throws {
        guard let logURL = latestLogURL() else { throw XCTSkip("No local UMP logs found") }
        let data = try Data(contentsOf: logURL)
        guard let text = String(data: data, encoding: .utf8) else { return }
        var c = Canvas2D(zoom: 1.0, translation: .zero)
        var checked = 0
        for line in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let topic = (obj["topic"] as? String) ?? ""
            guard let payload = (obj["data"] as? [String: Any])?["data"] as? [String: Any] else { continue }
            if topic == "ui.pan" {
                if let dx = payload["dx.doc"] as? Double, let dy = payload["dy.doc"] as? Double {
                    c.panBy(viewDelta: CGSize(width: dx * Double(c.zoom), height: dy * Double(c.zoom)))
                    checked += 1
                } else if let x = payload["x"] as? Double, let y = payload["y"] as? Double {
                    c.translation = CGPoint(x: x, y: y)
                }
            } else if topic == "ui.zoom" {
                if let ax = payload["anchor.view.x"] as? Double, let ay = payload["anchor.view.y"] as? Double, let mag = payload["magnification"] as? Double {
                    let before = c
                    c.zoomAround(viewAnchor: CGPoint(x: ax, y: ay), magnification: mag)
                    // Invariance: the anchor doc point remains under the anchor in view space (≤1 px drift)
                    let docAtAnchor = before.viewToDoc(CGPoint(x: ax, y: ay))
                    let afterView = c.docToView(docAtAnchor)
                    XCTAssertLessThan(abs(afterView.x - ax), 1.0)
                    XCTAssertLessThan(abs(afterView.y - ay), 1.0)
                    checked += 1
                } else if let z = payload["zoom"] as? Double {
                    c.zoom = z; c.clamp()
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "No applicable pan/zoom events found in log")
    }

    private func latestLogURL() -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        // Walk up to repo root (max 4 levels)
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent(".fountain/corpus/ump", isDirectory: true)
            if let items = try? fm.contentsOfDirectory(at: candidate, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]),
               let latest = items.filter({ $0.lastPathComponent.hasPrefix("stream-") && $0.pathExtension == "ndjson" }).sorted(by: { (a, b) in
                   let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                   let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                   return da > db
               }).first {
                return latest
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}

