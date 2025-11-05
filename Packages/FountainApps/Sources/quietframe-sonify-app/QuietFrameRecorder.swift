import Foundation
import AppKit
import AVFoundation
import FountainAudioEngine

@MainActor final class QuietFrameRecorder: ObservableObject {
    enum State { case idle, recording, stopping, finished(URL) }
    @Published private(set) var state: State = .idle

    private var writer: AVAssetWriter?
    private var vIn: AVAssetWriterInput?
    private var vAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var aIn: AVAssetWriterInput?
    private var tmpURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qf-instrument.mp4")
    private var start: CFAbsoluteTime = 0
    private var timer: Timer?
    private var windowId: CGWindowID = 0
    private var rect: CGRect = .zero

    func startRecording(window: NSWindow, rect: CGRect, fps: Int32 = 30) {
        guard case .idle = state else { return }
        self.windowId = CGWindowID(window.windowNumber)
        self.rect = rect
        try? FileManager.default.removeItem(at: tmpURL)
        do { try setupWriter(size: rect.size) } catch { print("[qfrec] setup error: \(error)"); return }
        writer?.startWriting(); writer?.startSession(atSourceTime: .zero)
        start = CFAbsoluteTimeGetCurrent()
        let interval = 1.0 / Double(fps)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.captureFrame() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Tap audio path for alignment: already audible; optional to add audio samples
        state = .recording
    }

    func stopRecording() {
        guard case .recording = state else { return }
        state = .stopping
        timer?.invalidate(); timer = nil
        vIn?.markAsFinished(); aIn?.markAsFinished()
        writer?.finishWriting { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.state = .finished(self.tmpURL) }
        }
    }

    private func setupWriter(size: CGSize) throws {
        let writer = try AVAssetWriter(outputURL: tmpURL, fileType: .mp4)
        let vSettings: [String: Any] = [ AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height) ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = true
        let adapt = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        aIn.expectsMediaDataInRealTime = true
        if writer.canAdd(vIn) { writer.add(vIn) }
        if writer.canAdd(aIn) { writer.add(aIn) }
        self.writer = writer; self.vIn = vIn; self.vAdaptor = adapt; self.aIn = aIn
    }

    private func captureFrame() {
        guard let vIn, let adaptor = vAdaptor, vIn.isReadyForMoreMediaData else { return }
        guard let img = CGWindowListCreateImage(rect, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .bestResolution]) else { return }
        var pb: CVPixelBuffer?
        let w = Int(rect.width), h = Int(rect.height)
        let attrs: [CFString: Any] = [ kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey: w, kCVPixelBufferHeightKey: h, kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary ]
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let px = pb else { return }
        CVPixelBufferLockBaseAddress(px, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(px), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(px), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        CVPixelBufferUnlockBaseAddress(px, [])
        let secs = CFAbsoluteTimeGetCurrent() - start
        adaptor.append(px, withPresentationTime: CMTime(seconds: secs, preferredTimescale: 1000))
    }
}
