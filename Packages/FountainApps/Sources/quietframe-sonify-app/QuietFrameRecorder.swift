import Foundation
import AppKit
import AVFoundation
import CoreMedia
import AudioToolbox
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
    private var writerQueue = DispatchQueue(label: "qfrec.writer")
    private var audioSampleRate: Double = 48000
    private var audioFramesWritten: Int64 = 0
    private var audioFormatDesc: CMAudioFormatDescription?

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
        // Install audio tap and begin muxing audio frames
        FountainAudioEngine.installAudioTap { [weak self] lptr, rptr, n, sr in
            guard let self else { return }
            let frames = n
            // Copy interleaved floats quickly
            let byteCount = Int(frames) * 2 * MemoryLayout<Float>.size
            var data = Data(count: byteCount)
            data.withUnsafeMutableBytes { dstRaw in
                let dst = dstRaw.bindMemory(to: Float.self).baseAddress!
                for i in 0..<Int(frames) {
                    dst[2*i] = lptr[i]
                    dst[2*i+1] = rptr[i]
                }
            }
            let copy = data
            self.writerQueue.async {
                Task { @MainActor in
                    self.appendAudioPCMInterleaved(data: copy, frames: Int(frames), sampleRate: sr)
                }
            }
        }
        QuietFrameRuntime.setRecState("recording")
        NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordStateChanged"), object: nil)
        state = .recording
    }

    func stopRecording() {
        guard case .recording = state else { return }
        state = .stopping
        timer?.invalidate(); timer = nil
        FountainAudioEngine.installAudioTap(nil)
        vIn?.markAsFinished(); aIn?.markAsFinished()
        writer?.finishWriting { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                QuietFrameRuntime.setRecState("idle")
                NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordStateChanged"), object: nil)
                self.state = .finished(self.tmpURL)
            }
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
        let aSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: audioSampleRate,
            AVEncoderBitRateKey: 192_000
        ]
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        aIn.expectsMediaDataInRealTime = true
        if writer.canAdd(vIn) { writer.add(vIn) }
        if writer.canAdd(aIn) { writer.add(aIn) }
        self.writer = writer; self.vIn = vIn; self.vAdaptor = adapt; self.aIn = aIn
        self.audioFramesWritten = 0
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

    // MARK: - Audio mux helpers
    private func ensureAudioFormatDescription(sampleRate: Double) {
        if let _ = audioFormatDesc, abs(sampleRate - audioSampleRate) < 1 { return }
        audioSampleRate = sampleRate
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var fmt: CMAudioFormatDescription?
        let result = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
        if result == noErr, let fmtDesc = fmt { audioFormatDesc = fmtDesc }
    }

    private func appendAudioPCMInterleaved(data: Data, frames: Int, sampleRate: Double) {
        guard let aIn, aIn.isReadyForMoreMediaData else { return }
        ensureAudioFormatDescription(sampleRate: sampleRate)
        guard let fmt = audioFormatDesc else { return }
        var bb: CMBlockBuffer?
        let byteCount = data.count
        guard CMBlockBufferCreateEmpty(allocator: kCFAllocatorDefault, capacity: 0, flags: 0, blockBufferOut: &bb) == kCMBlockBufferNoErr, let bb else { return }
        guard CMBlockBufferAppendMemoryBlock(bb, memoryBlock: nil, length: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: 0) == kCMBlockBufferNoErr else { return }
        data.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: byteCount)
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(value: audioFramesWritten, timescale: CMTimeScale(sampleRate)),
            decodeTimeStamp: .invalid
        )
        var sb: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: bb, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: fmt, sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sb)
        if status == noErr, let sb {
            if aIn.append(sb) { audioFramesWritten += Int64(frames) }
        }
    }
}
