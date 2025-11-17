import Foundation
import AppKit
import AVFoundation
import CoreMedia
import AudioToolbox
@preconcurrency import ScreenCaptureKit
import FountainAudioEngine
import QuietFrameKit

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
    // ScreenCaptureKit
    private var scStream: SCStream?
    private var scOutput: RecorderStreamOutput?
    private var scConfig: SCStreamConfiguration?
    // Audio ring + drain timer
    private var ring: AudioRingBuffer? = nil
    private var drainTimer: DispatchSourceTimer? = nil

    func startRecording(window: NSWindow, rect: CGRect, fps: Int32 = 30) {
        guard case .idle = state else { return }
        self.windowId = CGWindowID(window.windowNumber)
        self.rect = rect
        try? FileManager.default.removeItem(at: tmpURL)
        do { try setupWriter(size: rect.size) } catch { print("[qfrec] setup error: \(error)"); return }
        writer?.startWriting(); writer?.startSession(atSourceTime: .zero)
        start = CFAbsoluteTimeGetCurrent()
        // Start ScreenCaptureKit stream (macOS 14+). Falls back to timer capture if stream fails.
        Task { @MainActor in
            await self.startSCStreamFor(window: window, fps: fps)
        }
        // Install audio tap and begin muxing audio frames
        ring = AudioRingBuffer(capacityFrames: Int(2.0 * audioSampleRate)) // 2 seconds
        FountainAudioEngine.installAudioTap { [weak self] lptr, rptr, n, sr in
            guard let self else { return }
            _ = self.ring?.writeStereo(left: lptr, right: rptr, frames: Int(n))
            self.audioSampleRate = sr
        }
        // Drain at ~20 ms to keep UI main actor light
        let timer = DispatchSource.makeTimerSource(queue: writerQueue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.drainRingOnce() }
        timer.resume()
        self.drainTimer = timer
        QuietFrameRuntime.setRecState("recording")
        NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordStateChanged"), object: nil)
        state = .recording
    }

    func stopRecording() {
        guard case .recording = state else { return }
        state = .stopping
        timer?.invalidate(); timer = nil
        FountainAudioEngine.installAudioTap(nil)
        drainTimer?.cancel(); drainTimer = nil
        vIn?.markAsFinished(); aIn?.markAsFinished()
        // Stop ScreenCaptureKit stream
        if let scStream { try? scStream.stopCapture() }
        scStream = nil; scOutput = nil; scConfig = nil
        writer?.finishWriting { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                QuietFrameRuntime.setRecState("idle")
                NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordStateChanged"), object: nil)
                self.presentSaveAndNotify()
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

    private func drainRingOnce() {
        guard let ring else { return }
        let framesPerPacket = max(1, Int(audioSampleRate / 50)) // ~20 ms
        var data = Data()
        let got = ring.readInterleaved(into: &data, frames: framesPerPacket)
        if got > 0 {
            let copy = data
            Task { @MainActor in
                self.appendAudioPCMInterleaved(data: copy, frames: got, sampleRate: self.audioSampleRate)
            }
        }
    }

    // MARK: - Save As and vendor notify
    @MainActor private func presentSaveAndNotify() {
        let duration = (audioSampleRate > 0) ? Double(audioFramesWritten) / audioSampleRate : max(0, CFAbsoluteTimeGetCurrent() - start)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "QuietFrame-\(Int(Date().timeIntervalSince1970)).mp4"
        var finalURL = tmpURL
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: tmpURL, to: dest)
                finalURL = dest
            } catch {
                // keep tmp on failure
            }
        }
        // Inform companion via runtime sidecar vendor JSON (authoritative path)
        SidecarBridge.shared.sendVendor(topic: "rec.saved", data: [
            "url": finalURL.absoluteString,
            "durationSec": duration
        ])
        self.state = .finished(finalURL)
    }

    // MARK: - ScreenCaptureKit video pipeline
    @MainActor private func startSCStreamFor(window: NSWindow, fps: Int32) async {
        guard #available(macOS 13.0, *) else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { Int($0.windowID) == window.windowNumber }) else {
                // Fallback: timer-based capture
                let interval = 1.0 / Double(fps)
                let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.captureFrame() } }
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let cfg = SCStreamConfiguration()
            cfg.width = Int(rect.width)
            cfg.height = Int(rect.height)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.showsCursor = false
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: fps)
            let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
            let output = RecorderStreamOutput(owner: self)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
            try await stream.startCapture()
            self.scStream = stream
            self.scOutput = output
            self.scConfig = cfg
        } catch {
            // Fallback to timer-based capture
            let interval = 1.0 / Double(fps)
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.captureFrame() } }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
    }

    @MainActor fileprivate func appendVideo(sampleBuffer: CMSampleBuffer) {
        guard let vIn, let adaptor = vAdaptor, vIn.isReadyForMoreMediaData else { return }
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        adaptor.append(px, withPresentationTime: pts)
    }
}

@available(macOS 13.0, *)
private final class RecorderStreamOutput: NSObject, @preconcurrency SCStreamOutput {
    weak var owner: QuietFrameRecorder?
    init(owner: QuietFrameRecorder) { self.owner = owner }
    @MainActor func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let owner else { return }
        owner.appendVideo(sampleBuffer: sampleBuffer)
    }
}
