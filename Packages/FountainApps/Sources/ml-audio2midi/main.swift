import Foundation
import AVFoundation
import CoreMLKit
import MIDI2Transports
import ArgumentParser

struct MLAudio2MIDIDemo: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Audio → (ML pitch or DSP) → MIDI 2.0 demo")

    @Option(name: .shortAndLong, help: "Path to Core ML model (.mlmodel or .mlmodelc). If omitted, use DSP fallback.")
    var model: String?

    @Option(name: .shortAndLong, help: "Audio file path (wav/aiff). If omitted, use default microphone.")
    var file: String?

    @Option(name: .long, help: "CoreMIDI destination name. If omitted, publish virtual endpoints only.")
    var destination: String?

    @Option(name: .long, help: "MIDI 2.0 group (0-15).")
    var group: UInt8 = 0

    @Option(name: .long, help: "Channel (0-15).")
    var channel: UInt8 = 0

    @Option(name: .long, help: "Min confidence (0..1) for ML pitch to be considered.")
    var minConfidence: Float = 0.5

    @Option(name: .long, help: "Optional JSON mapping/properties file to publish via CI vendor JSON")
    var mapFile: String?

    @Flag(name: .long, help: "Publish mapping/properties snapshot at startup and on CI Inquiry")
    var publishMap: Bool = false
    @Flag(name: .long, help: "Render audio locally (in-process) in addition to sending MIDI")
    var render: Bool = false

    func run() throws {
        let runner = Runner(
            modelPath: model,
            filePath: file,
            destinationName: destination,
            group: group,
            channel: channel,
            minConfidence: minConfidence,
            mapFile: mapFile,
            publishMap: publishMap
        )
        runner.enableRender = render
        try runner.start()
    }

}

// Entry point
MLAudio2MIDIDemo.main()

final class Runner {
    private let modelPath: String?
    private let filePath: String?
    private let destinationName: String?
    private let group: UInt8
    private let channel: UInt8
    private let minConfidence: Float
    private let mapFile: String?
    private let publishMap: Bool
    var enableRender: Bool = false
    var synth: LocalRenderSynth? = nil
    private var lastNote: Int? = nil
    private var noteOn: Bool = false

    init(modelPath: String?, filePath: String?, destinationName: String?, group: UInt8, channel: UInt8, minConfidence: Float, mapFile: String?, publishMap: Bool) {
        self.modelPath = modelPath
        self.filePath = filePath
        self.destinationName = destinationName
        self.group = group
        self.channel = channel
        self.minConfidence = minConfidence
        self.mapFile = mapFile
        self.publishMap = publishMap
    }

    func start() throws {
        print("[ml-audio2midi] starting…")
        let transport = try openMIDITransport(name: "MLAudio2MIDI", destinationName: destinationName)
        let loadedModel: CoreMLInterop.LoadedModel? = try modelPath.map { try CoreMLInterop.loadModel(at: $0) }
        if let lm = loadedModel {
            let sum = ModelInfo.summarize(lm.model)
            let ins = sum.inputs.map { "\($0.name):\($0.shape)" }.joined(separator: ", ")
            let outs = sum.outputs.map { "\($0.name):\($0.shape)" }.joined(separator: ", ")
            print("[ml] loaded: \(lm.url.lastPathComponent) inputs=[\(ins)] outputs=[\(outs)]")
        } else {
            print("[ml] no model path provided, using DSP fallback (autocorr)")
        }
        if let path = filePath { try runFile(path: path, model: loadedModel, transport: transport) }
        else { try runMic(model: loadedModel, transport: transport) }
    }

    // MARK: - Audio from file
    private func runFile(path: String, model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) throws {
        let url = URL(fileURLWithPath: path)
        let af = try AVAudioFile(forReading: url)
        print("[audio] file: \(url.lastPathComponent) sr=\(af.fileFormat.sampleRate) ch=\(af.fileFormat.channelCount)")
        let buf = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: AVAudioFrameCount(af.length))!
        try af.read(into: buf)
        let samples = resampleToMono16k(buffer: buf)
        processStream(samples: samples, sr: 16000, model: model, transport: transport)
    }

    // MARK: - Microphone
    private func runMic(model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        print("[audio] mic: sr=\(format.sampleRate) ch=\(format.channelCount)")
        var fifo: [Float] = []
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            let mono = self.resampleToMono16k(buffer: buf)
            fifo.append(contentsOf: mono)
            let frame = 1024
            while fifo.count >= frame {
                let chunk = Array(fifo.prefix(frame))
                fifo.removeFirst(frame)
                self.processFrame(frame: chunk, model: model, transport: transport)
            }
        }
        try engine.start()
        print("[audio] capturing… press Ctrl-C to stop")
        RunLoop.current.run()
    }

    // MARK: - Core processing
    private func processStream(samples: [Float], sr: Int, model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) {
        let hop = 512
        let win = 1024
        var i = 0
        while i + win <= samples.count {
            let frame = Array(samples[i..<(i+win)])
            processFrame(frame: frame, model: model, transport: transport)
            i += hop
        }
    }

    private func processFrame(frame: [Float], model: CoreMLInterop.LoadedModel?, transport: CoreMIDITransport) {
        let (hz, conf) = inferPitch(frame: frame, model: model)
        guard hz > 0 else { return }
        if let _ = model, conf < minConfidence { return }
        // Map to MIDI note and PB14 around +/-2 semitones
        let noteFloat = 69.0 + 12.0 * log2(Double(hz) / 440.0)
        let note = Int(lround(noteFloat))
        let bendSemis = max(-2.0, min(2.0, noteFloat - Double(note)))
        let pb14 = UInt16((bendSemis + 2.0) / 4.0 * 16383.0)
        do {
            if lastNote != note {
                if noteOn, let ln = lastNote { try transport.send(umpWords: packMIDI2NoteOff(group: group, channel: channel, note: UInt8(max(0, min(127, ln))), velocity7: 0)) }
                try transport.send(umpWords: packMIDI2NoteOn(group: group, channel: channel, note: UInt8(max(0, min(127, note))), velocity7: 100))
                lastNote = note; noteOn = true
                if enableRender { startSynthIfNeeded(); synth?.noteOn(note: UInt8(max(0, min(127, note))), velocity: 100) }
            }
            try transport.send(umpWords: packMIDI2PitchBend32(group: group, channel: channel, value32: UInt32(pb14) * 0x10001))
            if enableRender { synth?.pitchBend14(pb14) }
            print(String(format: "[pitch] f0=%.2fHz conf=%.2f note=%d pb14=%d", hz, conf, note, pb14))
        } catch {
            fputs("[midi] send error: \(error)\n", stderr)
        }
    }

    private func inferPitch(frame: [Float], model: CoreMLInterop.LoadedModel?) -> (Float, Float) {
        if let lm = model {
            // Generic handling: if an output looks like a 360-bin distribution, use CREPE mapping; if scalar, treat as Hz.
            do {
                // Try to match input shape with frame length
                let arr = try CoreMLInterop.makeMultiArray(frame, shape: [frame.count])
                let out = try CoreMLInterop.predict(model: lm.model, inputs: [lm.model.modelDescription.inputDescriptionsByName.first!.key: arr])
                if let (_, ma) = out.first {
                    let cnt = ma.count
                    if cnt == 1 { return (CoreMLInterop.toArray(ma).first ?? 0, 1) }
                    if cnt == 360 {
                        let probs = CoreMLInterop.toArray(ma)
                        return crepeDecode(probs: probs)
                    }
                }
            } catch {
                fputs("[ml] inference error: \(error)\n", stderr)
            }
        }
        // DSP fallback
        return acfPitch(frame: frame, sr: 16000)
    }

    // CREPE mapping: 360 bins, 20 cents per bin, base C1 = 32.703195 Hz
    private func crepeDecode(probs: [Float]) -> (Float, Float) {
        guard probs.count == 360 else { return (0, 0) }
        var maxIdx = 0
        var maxVal: Float = -Float.infinity
        for i in 0..<probs.count { if probs[i] > maxVal { maxVal = probs[i]; maxIdx = i } }
        let f0 = Float(32.703195662574764 * pow(2.0, Double(maxIdx)/60.0))
        let conf = maxVal
        return (f0, conf)
    }

    // Simple autocorrelation pitch estimator (mono)
    private func acfPitch(frame: [Float], sr: Int) -> (Float, Float) {
        let minF: Float = 50, maxF: Float = 1000
        let minLag = Int(Float(sr)/maxF)
        let maxLag = Int(Float(sr)/minF)
        var bestLag = 0
        var best: Float = 0
        for lag in minLag..<maxLag {
            var sum: Float = 0
            var normA: Float = 0
            var normB: Float = 0
            var i = 0
            while i+lag < frame.count {
                let a = frame[i]
                let b = frame[i+lag]
                sum += a*b
                normA += a*a
                normB += b*b
                i += 1
            }
            let denom = sqrt(max(1e-8, normA*normB))
            let r = sum / denom
            if r > best { best = r; bestLag = lag }
        }
        let f0 = bestLag > 0 ? Float(sr)/Float(bestLag) : 0
        return (f0, best)
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

    // MARK: - MIDI helpers (MIDI 2.0 CV)
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

    private func packMIDI2PitchBend32(group: UInt8, channel: UInt8, value32: UInt32) -> [UInt32] {
        let type: UInt32 = 0x4
        let w1 = (type << 28)
            | (UInt32(group & 0xF) << 24)
            | (UInt32(0xE) << 20)
            | (UInt32(channel & 0xF) << 16)
        let w2 = value32
        return [w1, w2]
    }

    // MARK: - MIDI transport
    private func openMIDITransport(name: String, destinationName: String?) throws -> CoreMIDITransport {
        let t = CoreMIDITransport(name: name, destinationName: destinationName, enableVirtualEndpoints: true)
        try t.open()
        if publishMap {
            publishMappingSnapshot(transport: t)
        }
        t.onReceiveUMP = { words in
            let type = UInt8(((words.first ?? 0) >> 28) & 0xF)
            if type == 0x3 { // SysEx7
                let data = self.decodeSysEx7(words: words)
                if data.count >= 4 {
                    // Non-RT (0x7E), CI (0x0D), Discovery Inquiry (0x70)
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
            "device": "MLAudio2MIDI",
            "capabilities": ["pitch"],
            "mode": (modelPath != nil) ? "ml" : "dsp",
            "sampleRate": 16000,
            "window": 1024,
            "hop": 512,
            "minConfidence": minConfidence
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
            print("[ci] published pitch properties snapshot")
        }
    }

    // MIDI2 Instrument Bridge (local render)
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
            // Subsequent words would carry more bytes, but in 32-bit packets we only have two data bytes per word
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
