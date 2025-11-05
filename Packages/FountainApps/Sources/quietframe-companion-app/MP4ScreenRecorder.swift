// Reuse the recorder implementation for the companion app
@_exported import Foundation
@_exported import AppKit
@_exported import AVFoundation
@_exported import AVKit
@_exported import SwiftUI
@_exported import FountainAudioEngine
@preconcurrency import ScreenCaptureKit

// Pull in the existing implementation from the Sonify app (now removed from there)
// For now, we keep the code in this file for clarity.

@MainActor final class MP4ScreenRecorder: ObservableObject {
    enum State { case idle, recording, stopping, finished(URL) }
    @Published private(set) var state: State = .idle
    @Published var previewImage: NSImage? = nil
    @Published var duration: TimeInterval = 0
    var lastURL: URL? { if case .finished(let url) = state { return url } else { return nil } }
    var isRecording: Bool { if case .recording = state { return true } else { return false } }
    var canRecord: Bool { if case .idle = state { return true } else if case .finished = state { return true } else { return false } }
    var canStop: Bool { if case .recording = state { return true } else { return false } }
    var canSave: Bool { if case .finished = state { return true } else { return false } }

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    private var captureTimer: Timer?
    private var startTime: CFAbsoluteTime = 0
    private var frameCount: Int64 = 0
    private var fps: Int32 = 30
    private var targetWindowTitle: String = "QuietFrame Sonify"
    private var scStream: SCStream?
    private let streamQueue = DispatchQueue(label: "quietframe.rec.stream")
    private var tmpVideoURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quietframe-video.mp4")
    private var tmpAudioURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quietframe-audio.wav")
    private var metaInput: AVAssetWriterInput?
    private var metaAdaptor: AVAssetWriterInputMetadataAdaptor?
    private let metaTimescale: CMTimeScale = 1000

    func start(targetWindowTitle: String? = nil, fps: Int32 = 30) {
        switch state { case .idle, .finished: break; default: return }
        if let t = targetWindowTitle { self.targetWindowTitle = t }
        self.fps = fps
        self.frameCount = 0
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.duration = 0
        self.previewImage = nil
        try? FileManager.default.removeItem(at: tmpVideoURL)
        try? FileManager.default.removeItem(at: tmpAudioURL)
        // no sidecar metadata file
        Task { @MainActor in await self.beginStream() }
    }

    func stop() {
        guard case .recording = state else { return }
        state = .stopping
        captureTimer?.invalidate(); captureTimer = nil
        scStream?.stopCapture(completionHandler: { _ in })
        scStream = nil
        videoInput?.markAsFinished(); audioInput?.markAsFinished()
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
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: url, to: dst)
            }
        }
    }

    private func setupWriter(size: CGSize) throws {
        let writer = try AVAssetWriter(outputURL: tmpVideoURL, fileType: .mp4)
        let videoSettings: [String: Any] = [ AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height) ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        // Pass-through audio from ScreenCaptureKit sample buffers
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        aIn.expectsMediaDataInRealTime = true
        // Timed metadata track for UMP events
        let mIn = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil)
        mIn.expectsMediaDataInRealTime = true
        let mAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: mIn)
        if writer.canAdd(vIn) { writer.add(vIn) }
        if writer.canAdd(aIn) { writer.add(aIn) }
        if writer.canAdd(mIn) { writer.add(mIn) }
        self.writer = writer
        self.videoInput = vIn
        self.pixelAdaptor = adaptor
        self.audioInput = aIn
        self.metaInput = mIn
        self.metaAdaptor = mAdaptor
    }

    private func setupAudioFile(sampleRate: Double) throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: true)!
        let file = try AVAudioFile(forWriting: tmpAudioURL, settings: fmt.settings)
        self.audioFormat = fmt; self.audioFile = file
    }

    // ScreenCaptureKit stream setup
    private func beginStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let target = content.windows.first(where: { w in
                w.title?.localizedCaseInsensitiveContains(self.targetWindowTitle) == true
            }) else {
                print("[rec] target window not found: \(self.targetWindowTitle)")
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let cfg = SCStreamConfiguration()
            cfg.queueDepth = 8
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: fps)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            // Set output size from window frame
            let size = CGSize(width: max(640, Int(target.frame.width)), height: max(360, Int(target.frame.height)))
            cfg.width = Int(size.width)
            cfg.height = Int(size.height)
            try setupWriter(size: size)
            writer?.startWriting()
            writer?.startSession(atSourceTime: .zero)

            let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
            let output = StreamOutput(
                onVideo: { [weak self] pixelBuffer, pts in
                    guard let self, let adaptor = self.pixelAdaptor, let vIn = self.videoInput, vIn.isReadyForMoreMediaData else { return }
                    self.previewImage = NSImage(cgImage: CIContext().createCGImage(CIImage(cvImageBuffer: pixelBuffer), from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)))!, size: .zero)
                    _ = adaptor.append(pixelBuffer, withPresentationTime: pts)
                    self.duration = CFAbsoluteTimeGetCurrent() - self.startTime
                },
                onAudio: { [weak self] sample in
                    guard let self, let aIn = self.audioInput, aIn.isReadyForMoreMediaData else { return }
                    aIn.append(sample)
                }
            )
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: streamQueue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: streamQueue)
            self.scStream = stream
            state = .recording
            try await stream.startCapture()
        } catch {
            print("[rec] stream error: \(error)")
            state = .idle
        }
    }

    private func writePCM(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int, sampleRate: Double) {
        guard let file = audioFile, let fmt = audioFormat else { return }
        var data = [Float](repeating: 0, count: frames * 2)
        data.withUnsafeMutableBufferPointer { buf in
            let dst = buf.baseAddress!
            for i in 0..<frames { dst[i*2+0] = left[i]; dst[i*2+1] = right[i] }
        }
        if let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)) {
            pcm.frameLength = AVAudioFrameCount(frames)
            pcm.floatChannelData!.pointee.update(from: data, count: frames*2)
            try? file.write(from: pcm)
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
            if export?.status == .completed {
                completion(outURL)
            } else {
                completion(nil)
            }
        }
    }

    // Append UMP/PE events as timed metadata entries in the MP4
    func appendMidiEvent(json: String) {
        guard let mIn = metaInput, let adaptor = metaAdaptor, mIn.isReadyForMoreMediaData else { return }
        let secs = max(0, CFAbsoluteTimeGetCurrent() - startTime)
        let pts = CMTime(seconds: secs, preferredTimescale: metaTimescale)
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataIdentifier("mdta:com.fountain.ump")
        item.value = json as (any NSCopying & NSObjectProtocol)
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        let group = AVTimedMetadataGroup(items: [item], timeRange: CMTimeRange(start: pts, duration: CMTime(value: 1, timescale: metaTimescale)))
        adaptor.append(group)
    }
}

final class StreamOutput: NSObject, SCStreamOutput {
    typealias VideoHandler = (CVPixelBuffer, CMTime) -> Void
    typealias AudioHandler = (CMSampleBuffer) -> Void
    private let onVideo: VideoHandler
    private let onAudio: AudioHandler
    init(onVideo: @escaping VideoHandler, onAudio: @escaping AudioHandler) { self.onVideo = onVideo; self.onAudio = onAudio }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) { onVideo(pb, CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) }
        case .audio:
            onAudio(sampleBuffer)
        case .microphone:
            // ignore for now
            break
        @unknown default:
            break
        }
    }
}

struct PlayerPaneView: View {
    @ObservedObject var recorder: MP4ScreenRecorder
    @State private var player: AVPlayer? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Spacer()
            }
            Group {
                if recorder.isRecording, let img = recorder.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .border(Color.red.opacity(0.5))
                    Text(String(format: "%.1f s", recorder.duration)).font(.caption).foregroundStyle(.secondary)
                } else if let url = recorder.lastURL {
                    AVPlayerViewRepresentable(url: url, player: $player)
                        .frame(maxWidth: .infinity, maxHeight: 280)
                } else {
                    ZStack {
                        Color(NSColor.windowBackgroundColor)
                        Text("No recording yet").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 260)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button { recorder.start(targetWindowTitle: "QuietFrame Sonify") } label: { Label("Record", systemImage: "record.circle") }
                .disabled(!recorder.canRecord)
                .tint(.red)

                Button { recorder.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                .disabled(!recorder.canStop)

                Button { recorder.saveAs() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .disabled(!recorder.canSave)
                Spacer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding(10)
        .frame(width: 360)
        .background(.thinMaterial)
        .onChange(of: recorder.lastURL) { _, newURL in if let url = newURL { player = AVPlayer(url: url) } }
    }
    private var statusText: String { switch recorder.state { case .idle: return "Idle"; case .recording: return "Recording"; case .stopping: return "Stopping…"; case .finished: return "Ready" } }
    private var statusIcon: String { switch recorder.state { case .idle: return "circle"; case .recording: return "record.circle.fill"; case .stopping: return "hourglass"; case .finished: return "play.circle" } }
    private var statusColor: Color { switch recorder.state { case .recording: return .red; case .stopping: return .orange; default: return .secondary } }
}

struct AVPlayerViewRepresentable: NSViewRepresentable {
    let url: URL
    @Binding var player: AVPlayer?
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.controlsStyle = .floating; v.showsFullScreenToggleButton = false; v.player = player ?? AVPlayer(url: url); return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) { if nsView.player == nil { nsView.player = player ?? AVPlayer(url: url) } }
}
