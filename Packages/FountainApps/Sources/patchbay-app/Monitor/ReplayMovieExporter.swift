import Foundation
import AppKit
import AVFoundation
import CoreVideo
import CoreGraphics
import SwiftUI

@MainActor
enum ReplayMovieExporter {
    static func exportMovie(from logURL: URL, to outURL: URL, width: Int = 1440, height: Int = 900, fps: Int32 = 10) async throws {
        let size = CGSize(width: width, height: height)
        // Prepare scene
        let vm = EditorVM()
        let state = AppState()
        let host = NSHostingView(rootView: MetalCanvasHost().environmentObject(vm).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()

        // Prepare writer
        if FileManager.default.fileExists(atPath: outURL.path) {
            try? FileManager.default.removeItem(at: outURL)
        }
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAverageBitRateKey: width * height * 5
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferBytesPerRowAlignmentKey as String: width * 4
        ])
        guard writer.canAdd(input) else { throw NSError(domain: "ReplayMovie", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"]) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "ReplayMovie", code: 3, userInfo: nil) }
        writer.startSession(atSourceTime: .zero)

        // Read log lines
        guard let data = try? Data(contentsOf: logURL), let text = String(data: data, encoding: .utf8) else { return }
        var frame: Int64 = 0
        let timescale = fps
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        for line in text.split(separator: "\n") {
            if Task.isCancelled { break }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let topic = (obj["topic"] as? String) ?? "event"
            let payload = (obj["data"] as? [String: Any]) ?? [:]
            apply(topic: topic, payload: payload, vm: vm, state: state)
            // Render to CGImage
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let cgImage = rep.cgImage else { continue }
            // Build pixel buffer
            var pb: CVPixelBuffer? = nil
            let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pb)
            guard status == kCVReturnSuccess, let pixelBuffer = pb else { continue }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: colorSpace, bitmapInfo: bitmapInfo) {
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            let pts = CMTime(value: frame, timescale: timescale)
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: pts)
            frame += 1
        }
        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
            }
        }
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
        default:
            break
        }
    }
}
