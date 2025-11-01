#if canImport(AppKit)
import XCTest
import AppKit
import SwiftUI
@testable import patchbay_app

/// Visual snapshot tests for the PatchBay Test Scene (host‑owned Flow overlay).
/// Uses canonical node positions and edges from the approved prompt.
@MainActor
final class PatchBayTestSceneSnapshotTests: XCTestCase {

    private func makeHost(width: CGFloat, height: CGFloat) -> NSHostingView<EditorCanvas> {
        let vm = EditorVM()
        vm.grid = 24
        vm.zoom = 1.0
        // Canonical nodes (doc coordinates) from the prompt
        vm.nodes = [
            PBNode(id: "n-editor", title: "Fountain Editor", x: 100, y: 100, w: 120, h: 40,
                   ports: [ .init(id: "text", side: .right, dir: .output) ]),
            PBNode(id: "n-submit", title: "Submit", x: 380, y: 120, w: 120, h: 40,
                   ports: [ .init(id: "in", side: .left, dir: .input), .init(id: "out", side: .right, dir: .output) ]),
            PBNode(id: "n-corpus", title: "Corpus Instrument", x: 640, y: 100, w: 120, h: 40,
                   ports: [ .init(id: "in", side: .left, dir: .input) ]),
            PBNode(id: "n-llm", title: "LLM Adapter", x: 640, y: 280, w: 120, h: 40,
                   ports: [ .init(id: "in", side: .left, dir: .input) ])
        ]
        // Canonical edges: Editor → Submit → Corpus; Editor → LLM
        vm.edges = [
            PBEdge(from: "n-editor.text", to: "n-submit.in"),
            PBEdge(from: "n-submit.out", to: "n-corpus.in"),
            PBEdge(from: "n-editor.text", to: "n-llm.in")
        ]
        let view = EditorCanvas().environmentObject(vm).environmentObject(AppState())
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func snapshot(_ host: NSHostingView<EditorCanvas>) -> NSBitmapImageRep {
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func writeCandidate(_ rep: NSBitmapImageRep, name: String) {
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        img.addRepresentation(rep)
        if let tiff = img.tiffRepresentation {
            let dir = URL(fileURLWithPath: ".fountain/artifacts", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent(name)
            try? tiff.write(to: out)
        }
    }

    func testSceneSnapshot_1440x900_orWrites() throws {
        // Try to load baseline resource; if missing, write a candidate and skip
        let bundle = Bundle.module
        guard let baselineURL = bundle.url(forResource: "scene-patchbay-1440x900", withExtension: "tiff") else {
            let host = makeHost(width: 1440, height: 900)
            let rep = snapshot(host)
            writeCandidate(rep, name: "scene-patchbay-1440x900.tiff")
            throw XCTSkip("Baseline not found. Candidate written to .fountain/artifacts/scene-patchbay-1440x900.tiff")
        }
        let host = makeHost(width: 1440, height: 900)
        let rep = snapshot(host)
        let baseline = NSBitmapImageRep(data: try Data(contentsOf: baselineURL))!
        let (diff, heat) = SnapshotDiffTests.rmseDiffAndHeatmap(a: baseline, b: rep)
        if diff > 5.0, let img = heat, let data = img.tiffRepresentation {
            let out = URL(fileURLWithPath: ".fountain/artifacts/scene-patchbay-1440x900-heatmap.tiff")
            try? data.write(to: out)
        }
        XCTAssertLessThan(diff, 5.0)
    }

    func testSceneSnapshot_1280x800_orWrites() throws {
        let bundle = Bundle.module
        guard let baselineURL = bundle.url(forResource: "scene-patchbay-1280x800", withExtension: "tiff") else {
            let host = makeHost(width: 1280, height: 800)
            let rep = snapshot(host)
            writeCandidate(rep, name: "scene-patchbay-1280x800.tiff")
            throw XCTSkip("Baseline not found. Candidate written to .fountain/artifacts/scene-patchbay-1280x800.tiff")
        }
        let host = makeHost(width: 1280, height: 800)
        let rep = snapshot(host)
        let baseline = NSBitmapImageRep(data: try Data(contentsOf: baselineURL))!
        let (diff, heat) = SnapshotDiffTests.rmseDiffAndHeatmap(a: baseline, b: rep)
        if diff > 5.0, let img = heat, let data = img.tiffRepresentation {
            let out = URL(fileURLWithPath: ".fountain/artifacts/scene-patchbay-1280x800-heatmap.tiff")
            try? data.write(to: out)
        }
        XCTAssertLessThan(diff, 5.0)
    }
}
#endif

