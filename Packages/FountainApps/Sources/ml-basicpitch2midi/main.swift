import Foundation
import AVFoundation
import CoreMLKit
import MIDI2Transports
import ArgumentParser
import Accelerate

struct MLBasicPitch2MIDIDemo: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Audio → (BasicPitch-like ML or spectral) → polyphonic MIDI 2.0")

    @Option(name: .shortAndLong, help: "Path to Core ML model (.mlmodel or .mlmodelc). If omitted, use spectral poly fallback.")
    var model: String?

    @Option(name: .shortAndLong, help: "Audio file path (wav/aiff). If omitted, use default microphone.")
    var file: String?

    @Option(name: .long, help: "CoreMIDI destination name. If omitted, publish virtual endpoints only.")
    var destination: String?

    @Option(name: .long, help: "MIDI 2.0 group (0-15).")
    var group: UInt8 = 0

    @Option(name: .long, help: "Channel (0-15).")
    var channel: UInt8 = 0

    @Option(name: .long, help: "Probability threshold for note activation (0..1).")
    var threshold: Float = 0.5

    @Option(name: .long, help: "Maximum simultaneous notes to emit in fallback mode.")
    var maxNotes: Int = 6

    @Option(name: .long, help: "Optional JSON mapping/properties file to publish via CI vendor JSON")
    var mapFile: String?

    @Flag(name: .long, help: "Publish mapping/properties snapshot at startup and on CI Inquiry")
    var publishMap: Bool = false

    @Flag(name: .long, help: "Render audio locally (in-process) in addition to sending MIDI")
    var render: Bool = false

    func run() throws {
        let runner = Runner(modelPath: model, filePath: file, destinationName: destination, group: group, channel: channel, threshold: threshold, maxNotes: maxNotes, mapFile: mapFile, publishMap: publishMap)
        runner.enableRender = render
        try runner.start()
    }
}

MLBasicPitch2MIDIDemo.main()

final class Runner {
    private let modelPath: String?
    private let filePath: String?
    private let destinationName: String?
    private let group: UInt8
    private let channel: UInt8
    private let threshold: Float
    private let maxNotes: Int
    private let mapFile: String?
    private let publishMap: Bool
    var enableRender: Bool = false
    var synth: LocalRenderSynth? = nil

    init(modelPath: String?, filePath: String?, destinationName: String?, group: UInt8, channel: UInt8, threshold: Float, maxNotes: Int, mapFile: String?, publishMap: Bool) {
        self.modelPath = modelPath
        self.filePath = filePath
        self.destinationName = destinationName
        self.group = group
        self.channel = channel
        self.threshold = threshold
        self.maxNotes = maxNotes
        self.mapFile = mapFile
        self.publishMap = publishMap
    }

    private var active: Set<Int> = []

    func start() throws {
        print("[ml-basicpitch2midi] starting…")
        let transport = try openMIDITransport(name: "MLBasicPitch2MIDI", destinationName: destinationName)
        let loadedModel: CoreMLInterop.LoadedModel? = try modelPath.map { try CoreMLInterop.loadModel(at: $0) }
        if let lm = loadedModel {
            let sum = ModelInfo.summarize(lm.model)
            let ins = sum.inputs.map { "\($0.name):\($0.shape)" }.joined(separator: ", ")
            let outs = sum.outputs.map { "\($0.name):\($0.shape)" }.joined(separator: ", ")
            print("[ml] loaded: \(lm.url.lastPathComponent) inputs=[\(ins)] outputs=[\(outs)]")
        } else {
            print("[ml] no model path provided, using spectral poly fallback")
        }
        if let path = filePath { try runFile(path: path, model: loadedModel, transport: transport) }
        else { try runMic(model: loadedModel, transport: transport) }
    }

    private func runFile(path: String, model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) throws {
        let url = URL(fileURLWithPath: path)
        let af = try AVAudioFile(forReading: url)
        print("[audio] file: \(url.lastPathComponent) sr=\(af.fileFormat.sampleRate) ch=\(af.fileFormat.channelCount)")
        let buf = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: AVAudioFrameCount(af.length))!
        try af.read(into: buf)
        let samples = resampleToMono16k(buffer: buf)
        processStream(samples: samples, sr: 16000, model: model, transport: transport)
    }

    private func runMic(model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        print("[audio] mic: sr=\(format.sampleRate) ch=\(format.channelCount)")
        var fifo: [Float] = []
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            let mono = self.resampleToMono16k(buffer: buf)
            fifo.append(contentsOf: mono)
            let frame = 2048
            while fifo.count >= frame {
                let chunk = Array(fifo.prefix(frame))
                fifo.removeFirst(frame)
                self.processFrame(frame: chunk, model: model, transport: transport, hop: 512)
            }
        }
        try engine.start()
        print("[audio] capturing… press Ctrl-C to stop")
        RunLoop.current.run()
    }

    private func processStream(samples: [Float], sr: Int, model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) {
        let hop = 512
        let win = 2048
        var i = 0
        while i + win <= samples.count {
            let frame = Array(samples[i..<(i+win)])
            processFrame(frame: frame, model: model, transport: transport, hop: hop)
            i += hop
        }
    }

    private func processFrame(frame: [Float], model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport, hop: Int) {
        let probs: [Float]
        let pitchCount: Int
        if let lm = model {
            do {
                // Generic: try shape [pitches] or [frames, pitches] or [pitches, frames]
                let arr = try CoreMLInterop.makeMultiArray(frame, shape: [frame.count])
                let out = try CoreMLInterop.predict(model: lm.model, inputs: [lm.model.modelDescription.inputDescriptionsByName.first!.key: arr])
                guard let first = out.first?.value else { return }
                let shape = first.shape.map { Int(truncating: $0) }
                let v = CoreMLInterop.toArray(first)
                if shape.count == 1 { probs = v; pitchCount = v.count }
                else if shape.count == 2 {
                    // assume [frames, pitches] or [pitches, frames], take the most recent frame
                    let a = shape[0], b = shape[1]
                    if a == v.count / b { // [frames, pitches]
                        pitchCount = b
                        probs = Array(v.suffix(b))
                    } else if b == v.count / a { // [pitches, frames]
                        pitchCount = a
                        // gather last column
                        var last = [Float](repeating: 0, count: a)
                        for i in 0..<a { last[i] = v[i*b + (b-1)] }
                        probs = last
                    } else { return }
                } else { return }
            } catch {
                fputs("[ml] inference error: \(error)\n", stderr)
                return
            }
        } else {
            // Spectral fallback: pick top K peaks mapped to nearest MIDI notes
            let (notes, _) = topNotesFromSpectrum(frame: frame, sr: 16000, maxNotes: maxNotes)
            emitNotes(targetNotes: Set(notes), transport: transport)
            return
        }

        // Threshold + hysteresis
        var target = Set<Int>()
        for (i, p) in probs.enumerated() where p >= threshold {
            // Map pitch index to MIDI note (assume 128 classes centered on 21..108 or 88-key range)
            // Default: 88-key A0(21)..C8(108) if pitchCount==88, else 128 full range starting at 0.
            let note: Int
            if pitchCount == 88 { note = 21 + i }
            else if pitchCount == 128 { note = i }
            else { note = min(127, max(0, i)) }
            target.insert(note)
        }
        emitNotes(targetNotes: target, transport: transport)
    }

    private func emitNotes(targetNotes: Set<Int>, transport: CoreMIDITransport) {
        // Note-offs
        let offs = active.subtracting(targetNotes)
        for n in offs { try? transport.send(umpWords: packMIDI2NoteOff(group: group, channel: channel, note: UInt8(n), velocity7: 0)); if enableRender { synth?.noteOff(note: UInt8(n)) } }
        // Note-ons
        let ons = targetNotes.subtracting(active)
        for n in ons { try? transport.send(umpWords: packMIDI2NoteOn(group: group, channel: channel, note: UInt8(n), velocity7: 96)); if enableRender { startSynthIfNeeded(); synth?.noteOn(note: UInt8(n), velocity: 96) } }
        active = targetNotes
    }

    // MARK: - Fallback spectral peak picker
    private func topNotesFromSpectrum(frame: [Float], sr: Int, maxNotes: Int) -> ([Int], [Float]) {
        let n = frame.count
        let log2n = vDSP_Length(log2(Float(n)))
        var mags = [Float](repeating: 0, count: n/2)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return ([], []) }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = frame
        var imag = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { rbp in
            imag.withUnsafeMutableBufferPointer { ibp in
                var split = DSPSplitComplex(realp: rbp.baseAddress!, imagp: ibp.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n/2))
            }
        }
        // Simple peak picking
        var peaks: [(i: Int, v: Float)] = []
        for i in 2..<(mags.count-2) {
            let v = mags[i]
            if v > mags[i-1], v > mags[i+1] { peaks.append((i, v)) }
        }
        peaks.sort { $0.v > $1.v }
        let top = peaks.prefix(maxNotes)
        let hzPerBin = Float(sr) / Float(n)
        let notes = top.map { p -> Int in
            let hz = Float(p.i) * hzPerBin
            let nf = 69.0 + 12.0 * log2(Double(hz) / 440.0)
            return max(0, min(127, Int(lround(nf))))
        }
        return (notes, top.map { $0.v })
    }

    // MARK: - Audio utils
    private func resampleToMono16k(buffer: AVAudioPCMBuffer) -> [Float] {
        let inFmt = buffer.format
        let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        if inFmt == outFmt {
            let ch0 = buffer.floatChannelData![0]
            return Array(UnsafeBufferPointer(start: ch0, count: Int(buffer.frameLength)))
        }
        let converter = AVAudioConverter(from: inFmt, to: outFmt)!
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * (outFmt.sampleRate / inFmt.sampleRate) + 1024))!
        var error: NSError?
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error { return [] }
        let ch0 = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ch0, count: Int(outBuf.frameLength)))
    }

    // MARK: - MIDI helpers
    private func packMIDI2NoteOn(group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8) -> [UInt32] {
        let type: UInt32 = 0x4
        let attrType: UInt32 = 0
        let w1 = (type << 28)
            | (UInt32(group & 0xF) << 24)
            | (UInt32(0x9) << 20)
            | (UInt32(channel & 0xF) << 16)
            | (UInt32(note) << 8)
            | attrType
        let vel16 = UInt32(velocity7) * 0x0101
        let w2 = (vel16 << 16)
        return [w1, w2]
    }
    private func packMIDI2NoteOff(group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8) -> [UInt32] {
        let type: UInt32 = 0x4
        let attrType: UInt32 = 0
        let w1 = (type << 28)
            | (UInt32(group & 0xF) << 24)
            | (UInt32(0x8) << 20)
            | (UInt32(channel & 0xF) << 16)
            | (UInt32(note) << 8)
            | attrType
        let vel16 = UInt32(velocity7) * 0x0101
        let w2 = (vel16 << 16)
        return [w1, w2]
    }

    private func openMIDITransport(name: String, destinationName: String?) throws -> CoreMIDITransport {
        let t = CoreMIDITransport(name: name, destinationName: destinationName, enableVirtualEndpoints: true)
        try t.open()
        if publishMap { publishMappingSnapshot(transport: t) }
        t.onReceiveUMP = { words in
            let type = UInt8(((words.first ?? 0) >> 28) & 0xF)
            if type == 0x3 { // SysEx7
                let data = self.decodeSysEx7(words: words)
                if data.count >= 4 {
                    if data[0] == 0x7E && data[2] == 0x0D && data[3] == 0x70 {
                        self.publishMappingSnapshot(transport: t)
                    }
                }
            } else {
                print(String(format: "[midi] RX type=%X words=%@", (words.first ?? 0) >> 28, words as NSArray))
            }
        }
        print("[midi] opened. dest=\(destinationName ?? "auto/virtual") sources=\(CoreMIDITransport.sourceNames().joined(separator: ", "))")
        return t
    }

    private func publishMappingSnapshot(transport: CoreMIDITransport) {
        var snapshot: [String: Any] = [
            "device": "MLBasicPitch2MIDI",
            "capabilities": ["poly"],
            "mode": modelPath == nil ? "spectral" : "ml",
            "threshold": threshold,
            "maxNotes": maxNotes
        ]
        if let mapFile = mapFile, let data = try? Data(contentsOf: URL(fileURLWithPath: mapFile)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            snapshot["properties"] = obj
        }
        if let json = try? JSONSerialization.data(withJSONObject: snapshot) {
            var payload: [UInt8] = [0x7E, 0x7F, 0x0D, 0x7C]
            payload.append(contentsOf: json)
            let reply = self.packSysEx7UMP(group: 0, bytes: payload)
            try? transport.send(umpWords: reply)
            print("[ci] published poly properties snapshot")
        }
    }

    // Local render bridge
    func startSynthIfNeeded() {
        if synth == nil {
            #if canImport(Midi2SamplerDSP)
            synth = SamplerSynth()
            #else
            synth = SineSynth()
            #endif
            synth?.start()
        }
    }

    // MARK: - SysEx7 helpers
    private func decodeSysEx7(words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        for w in words {
            let b0 = UInt8((w >> 24) & 0xFF)
            let b1 = UInt8((w >> 16) & 0xFF)
            let cnt = Int(b1 & 0x0F)
            let b2 = UInt8((w >> 8) & 0xFF)
            let b3 = UInt8(w & 0xFF)
            if b0 >> 4 != 0x3 { continue }
            if cnt >= 1 { out.append(b2) }
            if cnt >= 2 { out.append(b3) }
        }
        return out
    }
    private func packSysEx7UMP(group: UInt8, bytes: [UInt8]) -> [UInt32] {
        var words: [UInt32] = []
        let total = bytes.count
        let chunks: [[UInt8]] = stride(from: 0, to: total, by: 6).map { Array(bytes[$0..<min($0+6, total)]) }
        for (idx, chunk) in chunks.enumerated() {
            let isSingle = chunks.count == 1
            let isFirst = idx == 0
            let isLast = idx == chunks.count - 1
            let status: UInt8 = isSingle ? 0x0 : (isFirst ? 0x1 : (isLast ? 0x3 : 0x2))
            let num = UInt8(chunk.count)
            var b: [UInt8] = Array(repeating: 0, count: 8)
            b[0] = (0x3 << 4) | (group & 0xF)
            b[1] = (status << 4) | (num & 0xF)
            for i in 0..<Int(num) { b[2+i] = chunk[i] }
            let w1 = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
            let w2 = (UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7])
            words.append(contentsOf: [w1, w2])
        }
        return words
    }
}
