import Foundation
import AppKit
import FountainAudioEngine
import AVFoundation
import AVKit
import CoreImage

@MainActor final class MP4ScreenRecorder: ObservableObject {
    enum State { case idle, recording, stopping, finished(URL) }
    @Published private(set) var state: State = .idle
    @Published var previewImage: NSImage? = nil
    @Published var duration: TimeInterval = 0
    var lastURL: URL? {
        if case .finished(let url) = state { return url }
        return nil
    }
    var isRecording: Bool { if case .recording = state { return true } else { return false } }
    var canRecord: Bool { if case .idle = state { return true } else if case .finished = state { return true } else { return false } }
    var canStop: Bool { if case .recording = state { return true } else { return false } }
    var canSave: Bool { if case .finished = state { return true } else { return false } }

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var audioFile: AVAudioFile? // temporary PCM capture (wav)
    private var audioFormat: AVAudioFormat?
    private var captureTimer: Timer?
    private var startTime: CFAbsoluteTime = 0
    private var frameCount: Int64 = 0
    private var fps: Int32 = 30
    private var windowId: CGWindowID = 0
    private var renderRect: CGRect = .zero
    private var tmpVideoURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quietframe-video.mp4")
    private var tmpAudioURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quietframe-audio.wav")

    func start(window: NSWindow, rect: CGRect, fps: Int32 = 30, sampleRate: Double = 48000) {
        switch state {
        case .idle, .finished:
            break
        default:
            return
        }
        self.windowId = CGWindowID(window.windowNumber)
        self.renderRect = rect
        self.fps = fps
        self.frameCount = 0
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.duration = 0
        self.previewImage = nil
        // Remove old temp files
        try? FileManager.default.removeItem(at: tmpVideoURL)
        try? FileManager.default.removeItem(at: tmpAudioURL)
        do {
            try setupWriter(size: rect.size)
            try setupAudioFile(sampleRate: sampleRate)
        } catch {
            print("[rec] setup failed: \(error)")
            return
        }
        // Install audio tap to capture PCM
        FountainAudioEngine.installAudioTap { [weak self] lptr, rptr, frames, sr in
            self?.writePCM(left: lptr, right: rptr, frames: frames, sampleRate: sr)
        }
        // Start timer for frames
        let interval = 1.0 / Double(fps)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer
        writer?.startWriting()
        writer?.startSession(atSourceTime: .zero)
        state = .recording
    }

    func stop() {
        guard case .recording = state else { return }
        state = .stopping
        captureTimer?.invalidate(); captureTimer = nil
        FountainAudioEngine.installAudioTap(nil as ((UnsafePointer<Float>, UnsafePointer<Float>, Int, Double) -> Void)?)
        if #available(macOS 15.0, *) { audioFile?.close() }
        audioFile = nil
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer?.finishWriting { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.muxAudioVideo { url in
                    if let url { self.state = .finished(url) } else { self.state = .idle }
                }
            }
        }
    }

    func saveAs() {
        guard case .finished(let url) = state else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "quietframe-recording.mp4"
        panel.begin { resp in
            if resp == .OK, let dst = panel.url {
                do {
                    try? FileManager.default.removeItem(at: dst)
                    try FileManager.default.copyItem(at: url, to: dst)
                } catch { print("[rec] save failed: \(error)") }
            }
        }
    }

    // MARK: - Private
    private func setupWriter(size: CGSize) throws {
        let writer = try AVAssetWriter(outputURL: tmpVideoURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        // Audio track as passthrough (we will mux later)
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48000,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ])
        aIn.expectsMediaDataInRealTime = true
        if writer.canAdd(vIn) { writer.add(vIn) }
        if writer.canAdd(aIn) { writer.add(aIn) }
        self.writer = writer
        self.videoInput = vIn
        self.pixelAdaptor = adaptor
        self.audioInput = aIn
    }

    private func setupAudioFile(sampleRate: Double) throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: true)!
        let file = try AVAudioFile(forWriting: tmpAudioURL, settings: fmt.settings)
        self.audioFormat = fmt
        self.audioFile = file
    }

    private func captureFrame() {
        guard let input = videoInput, let adaptor = pixelAdaptor, input.isReadyForMoreMediaData else { return }
        let img = CGWindowListCreateImage(renderRect, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .bestResolution])
        guard let cg = img else { return }
        // Update preview
        let nsimg = NSImage(cgImage: cg, size: NSSize(width: renderRect.width, height: renderRect.height))
        self.previewImage = nsimg
        self.duration = CFAbsoluteTimeGetCurrent() - startTime
        var pb: CVPixelBuffer?
        let w = Int(renderRect.width), h = Int(renderRect.height)
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: w,
            kCVPixelBufferHeightKey: h,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let px = pb else { return }
        CVPixelBufferLockBaseAddress(px, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(px), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(px), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        CVPixelBufferUnlockBaseAddress(px, [])
        let frameTime = CMTime(value: frameCount, timescale: fps)
        adaptor.append(px, withPresentationTime: frameTime)
        frameCount += 1
    }

    private func writePCM(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int, sampleRate: Double) {
        guard let file = audioFile, let fmt = audioFormat else { return }
        // Interleave quickly into a temp buffer
        var data = [Float](repeating: 0, count: frames * 2)
        data.withUnsafeMutableBufferPointer { buf in
            let dst = buf.baseAddress!
            for i in 0..<frames {
                dst[i*2+0] = left[i]
                dst[i*2+1] = right[i]
            }
        }
        if let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)) {
            pcm.frameLength = AVAudioFrameCount(frames)
            pcm.floatChannelData!.pointee.update(from: data, count: frames*2)
            do { try file.write(from: pcm) } catch { print("[rec] audio write failed: \(error)") }
        }
    }

    private func muxAudioVideo(completion: @escaping (URL?) -> Void) {
        let videoAsset = AVURLAsset(url: tmpVideoURL)
        let audioAsset = AVURLAsset(url: tmpAudioURL)
        let mix = AVMutableComposition()
        guard let vTrack = videoAsset.tracks(withMediaType: .video).first else { completion(nil); return }
        let vComp = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try? vComp.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: vTrack, at: .zero)
        if let aTrack = audioAsset.tracks(withMediaType: .audio).first {
            let aComp = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            let dur = min(videoAsset.duration, audioAsset.duration)
            try? aComp.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: aTrack, at: .zero)
        }
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quietframe-final-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outURL)
        let export = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetHighestQuality)
        export?.outputURL = outURL
        export?.outputFileType = .mp4
        export?.shouldOptimizeForNetworkUse = true
        export?.exportAsynchronously {
            completion(export?.status == .completed ? outURL : nil)
        }
    }

    func reset() { state = .idle; previewImage = nil; duration = 0 }
}
