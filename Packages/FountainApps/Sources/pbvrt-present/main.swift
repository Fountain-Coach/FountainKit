import Foundation
import AVFoundation
import CoreGraphics

struct FrameSpec: Decodable { let path: String; let durationMs: Int; let label: String }
struct Timeline: Decodable { let frames: [FrameSpec] }

@main
struct PBVRTPresentApp {
    static func main() throws {
        var framesDir: String? = nil
        var outPath: String? = nil
        var fps: Int32 = 30
        var baselineWav: String? = nil
        var candidateWav: String? = nil
        var gapMs: Int = 150
        var openOut = false

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--frames-dir": framesDir = it.next()
            case "--out": outPath = it.next()
            case "--fps": if let v = it.next(), let n = Int32(v) { fps = n }
            case "--baseline-wav": baselineWav = it.next()
            case "--candidate-wav": candidateWav = it.next()
            case "--gap-ms": if let v = it.next(), let n = Int(v) { gapMs = n }
            case "--open": openOut = true
            case "-h", "--help":
                print("PBVRT Present — render MP4 from frames + audio")
                print("Usage: pbvrt-present --frames-dir <dir> --out demo.mp4 [--fps 30] [--baseline-wav a.wav] [--candidate-wav b.wav] [--gap-ms 150] [--open]")
                return
            default: break
            }
        }
        guard let dir = framesDir else { throw NSError(domain: "pbvrt-present", code: 2, userInfo: [NSLocalizedDescriptionKey: "--frames-dir required"]) }
        let out = outPath ?? (dir as NSString).appendingPathComponent("demo.mp4")
        let timelineURL = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("timeline.json"))
        let data = try Data(contentsOf: timelineURL)
        let tl = try JSONDecoder().decode(Timeline.self, from: data)
        guard let first = tl.frames.first else { throw NSError(domain: "pbvrt-present", code: 3, userInfo: [NSLocalizedDescriptionKey: "no frames"]) }
        let firstImg = try loadCGImage(path: first.path)
        let W = firstImg.width
        let H = firstImg.height

        // 1) Write silent video from frames
        let tmpVideo = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("demo_silent.mov"))
        try? FileManager.default.removeItem(at: tmpVideo)
        try writeVideo(frames: tl.frames, size: CGSize(width: W, height: H), fps: fps, to: tmpVideo)

        // 2) Compose audio if provided
        let comp = AVMutableComposition()
        // Video track
        let vasset = AVURLAsset(url: tmpVideo)
        if let vt = try vasset.tracks(withMediaType: .video).first {
            let vr = CMTimeRange(start: .zero, duration: vasset.duration)
            let vtOut = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try vtOut.insertTimeRange(vr, of: vt, at: .zero)
        }
        var cursor = CMTime.zero
        func addAudio(_ path: String) throws { let a = AVURLAsset(url: URL(fileURLWithPath: path)); if let at = try a.tracks(withMediaType: .audio).first { let ar = CMTimeRange(start: .zero, duration: a.duration); let out = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!; try out.insertTimeRange(ar, of: at, at: cursor); cursor = CMTimeAdd(cursor, a.duration) } }
        if let bw = baselineWav, FileManager.default.fileExists(atPath: bw) { try? addAudio(bw) }
        if gapMs > 0 { cursor = CMTimeAdd(cursor, CMTimeMake(value: Int64(gapMs), timescale: 1000)) }
        if let cw = candidateWav, FileManager.default.fileExists(atPath: cw) { try? addAudio(cw) }

        // 3) Export MP4
        let outURL = URL(fileURLWithPath: out)
        try? FileManager.default.removeItem(at: outURL)
        let ses = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
        ses.outputURL = outURL
        ses.outputFileType = .mp4
        let g = DispatchGroup(); g.enter(); ses.exportAsynchronously { g.leave() }; g.wait()
        if ses.status != .completed { throw NSError(domain: "pbvrt-present", code: 4, userInfo: [NSLocalizedDescriptionKey: "export failed: \(ses.error?.localizedDescription ?? "unknown")"]) }
        print(outURL.path)
        if openOut { _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: [outURL.path]) }
    }

    static func loadCGImage(path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "pbvrt-present", code: 10, userInfo: [NSLocalizedDescriptionKey: "bad image: \(path)"])
        }
        return img
    }

    static func writeVideo(frames: [FrameSpec], size: CGSize, fps: Int32, to url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let vinput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB), kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vinput, sourcePixelBufferAttributes: attrs)
        vinput.expectsMediaDataInRealTime = false
        writer.add(vinput)
        writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let frameDuration = CMTimeMake(value: 1, timescale: fps)
        var time = CMTime.zero
        let rgb = CGColorSpaceCreateDeviceRGB()
        for f in frames {
            autoreleasepool {
                guard let img = try? loadCGImage(path: f.path) else { return }
                let durFrames = max(1, Int(Double(f.durationMs)/1000.0 * Double(fps)))
                for _ in 0..<durFrames {
                    while !vinput.isReadyForMoreMediaData { usleep(1000) }
                    var px: CVPixelBuffer? = nil
                    CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs as CFDictionary, &px)
                    guard let buf = px else { continue }
                    CVPixelBufferLockBaseAddress(buf, [])
                    if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                        ctx.draw(img, in: CGRect(origin: .zero, size: size))
                    }
                    CVPixelBufferUnlockBaseAddress(buf, [])
                    adaptor.append(buf, withPresentationTime: time)
                    time = CMTimeAdd(time, frameDuration)
                }
            }
        }
        vinput.markAsFinished()
        let g = DispatchGroup(); g.enter(); writer.finishWriting { g.leave() }; g.wait()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "pbvrt-present", code: 11, userInfo: [NSLocalizedDescriptionKey: "writer failed"]) }
    }
}

