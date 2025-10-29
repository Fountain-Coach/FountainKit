import Foundation
import AppKit
import SwiftUI
import MetalViewKit
@main
struct ReplayExportMain {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        guard let first = args.first else {
            fputs("Usage: replay-export <path/to/log.ndjson> [--movie <out.mov>] [--size 1440x900]\n", stderr)
            exit(2)
        }
        let logURL = URL(fileURLWithPath: first)
        var width = 1440, height = 900
        var outMovie: URL? = nil
        var i = args.dropFirst().makeIterator()
        while let tok = i.next() {
            if tok == "--movie", let p = i.next() { outMovie = URL(fileURLWithPath: p) }
            else if tok == "--size", let s = i.next(), let x = s.split(separator: "x").map(String.init) as [String]?, x.count == 2, let w = Int(x[0]), let h = Int(x[1]) { width = w; height = h }
        }
        if let out = outMovie { await exportMovieStandalone(from: logURL, to: out, width: width, height: height) }
        else { await exportFramesStandalone(from: logURL, width: width, height: height) }
    }
}

// Standalone minimal replayer using MetalViewKit directly (no patchbay-app dependency)
@MainActor
private func exportFramesStandalone(from logURL: URL, width: Int, height: Int) async {
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    let outRoot = cwd.appendingPathComponent(".fountain/artifacts/replay", isDirectory: true)
    try? fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
    let name = logURL.deletingPathExtension().lastPathComponent
    let outDir = outRoot.appendingPathComponent(name, isDirectory: true)
    try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = MetalCanvasView(zoom: 1.0, translation: .zero, nodes: { ReplayScene.shared.nodes }, selected: { [] }, onSelect: { _ in }, onMoveBy: { _,_ in }, onTransformChanged: { _,_ in })
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()

    guard let text = try? String(contentsOf: logURL) else { return }
    var idx = 0
    for line in text.split(separator: "\n") {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
        let topic = (obj["topic"] as? String) ?? "event"
        let payload = (obj["data"] as? [String: Any]) ?? [:]
        ReplayScene.shared.apply(topic: topic, payload: payload)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: host.bounds.size); img.addRepresentation(rep)
            let frameName = String(format: "frame-%04d.tiff", idx)
            try? img.tiffRepresentation?.write(to: outDir.appendingPathComponent(frameName))
            idx += 1
        }
    }
    NSWorkspace.shared.open(outDir)
}

@MainActor
private func exportMovieStandalone(from logURL: URL, to outURL: URL, width: Int, height: Int) async {
    // Minimal: export frames then leave movie assembly as future work
    await exportFramesStandalone(from: logURL, width: width, height: height)
    print("Frames exported to .fountain/artifacts/replay; movie export not yet implemented in standalone tool")
}

// Minimal scene that interprets a subset of events, rendering Stage pages
@MainActor
final class ReplayScene {
    static let shared = ReplayScene()
    private init() {}
    var nodes: [MetalCanvasNode] = []
    private var zoom: CGFloat = 1.0
    private var translation: CGPoint = .zero
    func apply(topic: String, payload: [String: Any]) {
        switch topic {
        case "node.add":
            let id = (payload["id"] as? String) ?? UUID().uuidString
            let x = CGFloat((payload["x"] as? Int) ?? 0)
            let y = CGFloat((payload["y"] as? Int) ?? 0)
            let w = CGFloat((payload["w"] as? Int) ?? 595)
            let h = CGFloat((payload["h"] as? Int) ?? 842)
            // Treat every node as an A4 Stage
            let stage = StageMetalNode(id: id, frameDoc: CGRect(x: x, y: y, width: w, height: h), title: id, page: "A4", margins: .init(top: 18, left: 18, bottom: 18, right: 18), baseline: 12)
            // Replace or append
            if let i = nodes.firstIndex(where: { $0.id == id }) { nodes[i] = stage } else { nodes.append(stage) }
        case "node.move":
            if let id = payload["id"] as? String, let i = nodes.firstIndex(where: { $0.id == id }) {
                var f = nodes[i].frameDoc
                if let x = payload["x"] as? Int { f.origin.x = CGFloat(x) }
                if let y = payload["y"] as? Int { f.origin.y = CGFloat(y) }
                (nodes[i] as? StageMetalNode)?.frameDoc = f
            }
        case "node.resize":
            if let id = payload["id"] as? String, let i = nodes.firstIndex(where: { $0.id == id }) {
                var f = nodes[i].frameDoc
                if let w = payload["w"] as? Int { f.size.width = CGFloat(w) }
                if let h = payload["h"] as? Int { f.size.height = CGFloat(h) }
                (nodes[i] as? StageMetalNode)?.frameDoc = f
            }
        case "ui.pan":
            if let x = payload["x"] as? Double, let y = payload["y"] as? Double { translation = CGPoint(x: x, y: y) }
        case "ui.zoom":
            if let z = payload["zoom"] as? Double { zoom = CGFloat(z) }
        default: break
        }
    }
}
