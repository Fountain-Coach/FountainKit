import Foundation
import SwiftUI
import AppKit

@MainActor
enum ReplayExporter {
    struct EventRec: Codable {
        var topic: String
        var ts: String?
        var frame: String
        var index: Int
    }
    struct Index: Codable {
        var width: Int
        var height: Int
        var count: Int
        var events: [EventRec]
        var source: String
        var generatedAt: String
    }

    static func exportFrames(from logURL: URL, width: Int = 1440, height: Int = 900) async {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let outRoot = cwd.appendingPathComponent(".fountain/artifacts/replay", isDirectory: true)
        try? fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
        let name = logURL.deletingPathExtension().lastPathComponent
        let outDir = outRoot.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Prepare isolated canvas host (Metal)
        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()

        // Parse log
        guard let data = try? Data(contentsOf: logURL), let text = String(data: data, encoding: .utf8) else { return }
        var idx = 0
        var events: [EventRec] = []
        for line in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let topic = (obj["topic"] as? String) ?? "event"
            let ts = obj["ts"] as? String
            let payload = (obj["data"] as? [String: Any]) ?? [:]
            apply(topic: topic, payload: payload, vm: vm, state: state)
            // Render frame
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                let img = NSImage(size: host.bounds.size); img.addRepresentation(rep)
                let frameName = String(format: "frame-%04d.tiff", idx)
                let url = outDir.appendingPathComponent(frameName)
                try? img.tiffRepresentation?.write(to: url)
                events.append(EventRec(topic: topic, ts: ts, frame: frameName, index: idx))
                idx += 1
            }
        }
        // Write index
        let now = ISO8601DateFormatter().string(from: Date())
        let index = Index(width: width, height: height, count: idx, events: events, source: logURL.lastPathComponent, generatedAt: now)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? enc.encode(index) {
            try? json.write(to: outDir.appendingPathComponent("index.json"))
        }
        NSWorkspace.shared.open(outDir)
    }

    private static func apply(topic: String, payload: [String: Any], vm: EditorVM, state: AppState) {
        switch topic {
        case "node.add":
            guard let id = payload["id"] as? String else { return }
            let x = (payload["x"] as? Int) ?? 0
            let y = (payload["y"] as? Int) ?? 0
            let w = (payload["w"] as? Int) ?? max(1, vm.grid*10)
            let h = (payload["h"] as? Int) ?? max(1, vm.grid*6)
            if vm.node(by: id) == nil {
                vm.nodes.append(PBNode(id: id, title: id, x: x, y: y, w: w, h: h, ports: []))
                // Assume Stage by default for replay visualization
                state.registerDashNode(id: id, kind: .stageA4, props: ["title": id, "page": "A4", "margins": "18,18,18,18", "baseline": "12"])            
            }
        case "node.remove":
            if let id = payload["id"] as? String { vm.nodes.removeAll { $0.id == id } }
        case "node.move":
            if let id = payload["id"] as? String, let i = vm.nodeIndex(by: id) {
                if let x = payload["x"] as? Int { vm.nodes[i].x = x }
                if let y = payload["y"] as? Int { vm.nodes[i].y = y }
            }
        case "node.resize":
            if let id = payload["id"] as? String, let i = vm.nodeIndex(by: id) {
                if let w = payload["w"] as? Int { vm.nodes[i].w = w }
                if let h = payload["h"] as? Int { vm.nodes[i].h = h }
            }
        case "node.rename":
            if let id = payload["id"] as? String, let i = vm.nodeIndex(by: id) {
                let t = (payload["title"] as? String) ?? id
                vm.nodes[i].title = t
                state.updateDashProps(id: id, props: ["title": t, "page":"A4", "margins":"18,18,18,18", "baseline":"12"])            
            }
        case "wire.add":
            if let ref = payload["ref"] as? String {
                let parts = ref.split(separator: "→").map(String.init)
                if parts.count == 2 { vm.edges.append(PBEdge(from: parts[0], to: parts[1])) }
            }
        case "wire.remove":
            if let ref = payload["ref"] as? String { vm.edges.removeAll { ($0.from+"→"+$0.to) == ref } }
        case "selection.set":
            if let arr = payload["selected"] as? [Any] { vm.selected = Set(arr.compactMap { $0 as? String }); vm.selection = vm.selected.first }
        case "selection.change":
            if let arr = payload["after"] as? [Any] { vm.selected = Set(arr.compactMap { $0 as? String }); vm.selection = vm.selected.first }
        case "ui.pan":
            if let x = payload["x"] as? Double, let y = payload["y"] as? Double {
                vm.translation = CGPoint(x: x, y: y)
            } else {
                let dx = (payload["dx.doc"] as? Double) ?? 0
                let dy = (payload["dy.doc"] as? Double) ?? 0
                vm.translation = CGPoint(x: vm.translation.x + dx, y: vm.translation.y + dy)
            }
        case "ui.zoom":
            if let z = payload["zoom"] as? Double { vm.zoom = CGFloat(z) }
        default:
            break
        }
    }
}
