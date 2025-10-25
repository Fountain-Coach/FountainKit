import Foundation
import AVFoundation
import CoreMLKit
import CoreML
import MIDI2Transports
import ArgumentParser

@main
struct MLYamNet2MIDIDemo: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Audio → (YAMNet) → MIDI 2.0 scene changes")

    @Option(name: .shortAndLong, help: "Path to YAMNet Core ML model (.mlmodel/.mlmodelc)")
    var model: String = "Public/Models/YAMNet.mlmodel"

    @Option(name: .long, help: "Path to YAMNet class map CSV (yamnet_class_map.csv)")
    var labels: String = "Public/Models/yamnet_class_map.csv"

    @Option(name: .shortAndLong, help: "Audio file path (wav/aiff). If omitted, use microphone.")
    var file: String?

    @Option(name: .long, help: "CoreMIDI destination name. If omitted, publish virtual endpoints only.")
    var destination: String?

    @Option(name: .long, help: "MIDI 2.0 group (0-15)")
    var group: UInt8 = 0

    @Option(name: .long, help: "Channel (0-15)")
    var channel: UInt8 = 0

    @Option(name: .long, help: "Probability threshold for top class to trigger change (0..1)")
    var threshold: Float = 0.25

    @Option(name: .long, help: "Cooldown milliseconds between scene changes")
    var cooldownMs: Int = 1000

    @Flag(name: .long, help: "Send Program Change on scene change (maps label index → program)")
    var sendProgram: Bool = false

    @Option(name: .long, help: "Optional JSON mapping file (label→program or programMapByIndex)")
    var mapFile: String?

    @Flag(name: .long, help: "Publish scene mapping snapshot at startup and on CI Inquiry")
    var publishMap: Bool = false

    @Option(name: .long, help: "Fallback program (0-127) when label not mapped; default maps index % 128")
    var fallbackProgram: Int = -1

    func run() throws {
        let runner = Runner(modelPath: model,
                            labelsPath: labels,
                            filePath: file,
                            destinationName: destination,
                            group: group,
                            channel: channel,
                            threshold: threshold,
                            cooldownMs: cooldownMs,
                            sendProgram: sendProgram,
                            mapFile: mapFile,
                            publishMap: publishMap,
                            fallbackProgram: fallbackProgram)
        try runner.start()
    }
}

final class Runner {
    private let modelPath: String
    private let labelsPath: String
    private let filePath: String?
    private let destinationName: String?
    private let group: UInt8
    private let channel: UInt8
    private let threshold: Float
    private let cooldownMs: Int
    private let sendProgram: Bool
    private let mapFile: String?
    private let publishMap: Bool
    private let fallbackProgram: Int

    private var labels: [Int: String] = [:]
    private var programMapByLabel: [String: Int] = [:]
    private var programMapByIndex: [Int: Int] = [:]
    private var lastSceneIndex: Int? = nil
    private var lastChangeTime: CFAbsoluteTime = 0

    init(modelPath: String, labelsPath: String, filePath: String?, destinationName: String?, group: UInt8, channel: UInt8, threshold: Float, cooldownMs: Int, sendProgram: Bool, mapFile: String?, publishMap: Bool, fallbackProgram: Int) {
        self.modelPath = modelPath
        self.labelsPath = labelsPath
        self.filePath = filePath
        self.destinationName = destinationName
        self.group = group
        self.channel = channel
        self.threshold = threshold
        self.cooldownMs = cooldownMs
        self.sendProgram = sendProgram
        self.mapFile = mapFile
        self.publishMap = publishMap
        self.fallbackProgram = fallbackProgram
    }

    func start() throws {
        print("[ml-yamnet2midi] starting…")
        let transport = try openMIDITransport(name: "MLYamNet2MIDI", destinationName: destinationName)
        let loaded = try CoreMLInterop.loadModel(at: modelPath)
        loadLabels()
        loadProgramMap()
        let sum = ModelInfo.summarize(loaded.model)
        print("[ml] loaded: \(loaded.url.lastPathComponent) inputs=\(sum.inputs.map { "\($0.name):\($0.shape)" }.joined(separator: ", ")) outputs=\(sum.outputs.map { "\($0.name):\($0.shape)" }.joined(separator: ", "))")

        if let path = filePath { try runFile(path: path, model: loaded, transport: transport) }
        else { try runMic(model: loaded, transport: transport) }
    }

    private func runFile(path: String, model: CoreMLInterop.LoadedModel, transport: CoreMIDITransport) throws {
        let url = URL(fileURLWithPath: path)
        let af = try AVAudioFile(forReading: url)
        print("[audio] file: \(url.lastPathComponent) sr=\(af.fileFormat.sampleRate) ch=\(af.fileFormat.channelCount)")
        let buf = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: AVAudioFrameCount(af.length))!
        try af.read(into: buf)
        let samples = resampleToMono16k(buffer: buf)
        processStream(samples: samples, sr: 16000, model: model, transport: transport)
    }

    private func runMic(model: CoreMLInterop.LoadedModel, transport: CoreMIDITransport) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        print("[audio] mic: sr=\(format.sampleRate) ch=\(format.channelCount)")
        var fifo: [Float] = []
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            let mono = self.resampleToMono16k(buffer: buf)
            fifo.append(contentsOf: mono)
            // default YAMNet window ~ 0.96s @ 16k ≈ 15360; use 15600 to be safe
            let window = 15600
            let hop = 4000
            while fifo.count >= window {
                let chunk = Array(fifo.prefix(window))
                fifo.removeFirst(hop)
                self.processFrame(frame: chunk, model: model, transport: transport)
            }
        }
        try engine.start()
        print("[audio] capturing… press Ctrl-C to stop")
        RunLoop.current.run()
    }

    private func processStream(samples: [Float], sr: Int, model: CoreMLInterop.LoadedModel, transport: CoreMIDITransport) {
        let window = 15600
        let hop = 4000
        var i = 0
        while i + window <= samples.count {
            let frame = Array(samples[i..<(i+window)])
            processFrame(frame: frame, model: model, transport: transport)
            i += hop
        }
    }

    private func processFrame(frame: [Float], model: CoreMLInterop.LoadedModel, transport: CoreMIDITransport) {
        guard let (inputName, shape) = model.model.modelDescription.inputDescriptionsByName.first.map({ ($0.key, $0.value.multiArrayConstraint?.shape.map { $0.intValue } ?? []) }) else { return }
        let arr: MLMultiArray
        do {
            // Try to match shape: [N] or [1,N] commonly
            if shape.count == 1 {
                let n = shape[0] > 0 ? shape[0] : frame.count
                let x = frame.count == n ? frame : Array(frame.prefix(n))
                arr = try CoreMLInterop.makeMultiArray(x, shape: [n])
            } else if shape.count == 2 {
                let n = shape[1] > 0 ? shape[1] : frame.count
                let x = frame.count == n ? frame : Array(frame.prefix(n))
                arr = try CoreMLInterop.makeMultiArray(x, shape: [1, n])
            } else {
                arr = try CoreMLInterop.makeMultiArray(frame, shape: [frame.count])
            }
            let out = try CoreMLInterop.predict(model: model.model, inputs: [inputName: arr])
            guard let first = out.first else { return }
            let probs = CoreMLInterop.toArray(first.value)
            guard probs.count > 0 else { return }
            var maxIdx = 0
            var maxVal: Float = -Float.infinity
            for i in 0..<probs.count { if probs[i] > maxVal { maxVal = probs[i]; maxIdx = i } }
            handleScene(index: maxIdx, confidence: maxVal, transport: transport)
        } catch {
            fputs("[ml] inference error: \(error)\n", stderr)
        }
    }

    private func handleScene(index: Int, confidence: Float, transport: CoreMIDITransport) {
        let now = CFAbsoluteTimeGetCurrent()
        let cooldown = Double(cooldownMs) / 1000.0
        guard confidence >= threshold else { return }
        if let last = lastSceneIndex, last == index, now - lastChangeTime < cooldown { return }
        lastSceneIndex = index
        lastChangeTime = now
        let label = labels[index] ?? "class_\(index)"
        print(String(format: "[scene] %@ conf=%.2f", label, confidence))
        if sendProgram {
            let program = UInt8(programFor(index: index, label: label) % 128)
            try? transport.send(umpWords: packMIDI2ProgramChange(group: group, channel: channel, program: program))
        }
        // Publish vendor JSON snapshot via SysEx7
        let snapshot: [String: Any] = [
            "device": "MLYamNet2MIDI",
            "sceneIndex": index,
            "sceneLabel": label,
            "confidence": confidence
        ]
        if let json = try? JSONSerialization.data(withJSONObject: snapshot) {
            var payload: [UInt8] = [0x7E, 0x7F, 0x0D, 0x7C]
            payload.append(contentsOf: json)
            let reply = packSysEx7UMP(group: group, bytes: payload)
            try? transport.send(umpWords: reply)
        }
    }

    // MARK: - Labels
    private func loadLabels() {
        let url = URL(fileURLWithPath: labelsPath)
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return }
        for line in s.split(separator: "\n") {
            if line.hasPrefix("index,") { continue }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count >= 3, let idx = Int(parts[0]) {
                let name = String(parts[2])
                labels[idx] = name
            }
        }
        if labels.isEmpty { print("[labels] no labels loaded; falling back to class_<index>") }
    }

    private func loadProgramMap() {
        guard let mapFile = mapFile else { return }
        let url = URL(fileURLWithPath: mapFile)
        guard let data = try? Data(contentsOf: url) else { print("[map] could not read \(mapFile)"); return }
        do {
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let byLabel = obj["programMap"] as? [String: Any] {
                    for (k, v) in byLabel { if let p = v as? Int { programMapByLabel[k] = p } }
                }
                if let byIndex = obj["programMapByIndex"] as? [String: Any] {
                    for (k, v) in byIndex { if let i = Int(k), let p = v as? Int { programMapByIndex[i] = p } }
                }
            }
            print("[map] loaded: labels=\(programMapByLabel.count) indices=\(programMapByIndex.count)")
        } catch {
            print("[map] parse error: \(error)")
        }
    }

    private func programFor(index: Int, label: String) -> Int {
        if let p = programMapByLabel[label] { return p }
        if let p = programMapByIndex[index] { return p }
        if fallbackProgram >= 0 { return min(127, max(0, fallbackProgram)) }
        return index % 128
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
    private func packMIDI2ProgramChange(group: UInt8, channel: UInt8, program: UInt8) -> [UInt32] {
        let type: UInt32 = 0x4
        let w1 = (type << 28)
            | (UInt32(group & 0xF) << 24)
            | (UInt32(0xC) << 20)
            | (UInt32(channel & 0xF) << 16)
        let w2 = UInt32(program)
        return [w1, w2]
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

    private func openMIDITransport(name: String, destinationName: String?) throws -> CoreMIDITransport {
        let t = CoreMIDITransport(name: name, destinationName: destinationName, enableVirtualEndpoints: true)
        try t.open()
        if publishMap { publishMappingSnapshot(transport: t) }
        t.onReceiveUMP = { words in
            let type = UInt8(((words.first ?? 0) >> 28) & 0xF)
            if type == 0x3 {
                let data = self.decodeSysEx7(words: words)
                if data.count >= 4 && data[0] == 0x7E && data[2] == 0x0D && data[3] == 0x70 {
                    self.publishMappingSnapshot(transport: t)
                }
            }
        }
        print("[midi] opened. dest=\(destinationName ?? "auto/virtual") sources=\(CoreMIDITransport.sourceNames().joined(separator: ", "))")
        return t
    }

    // MARK: - CI vendor JSON mapping snapshot
    private func publishMappingSnapshot(transport: CoreMIDITransport) {
        var body: [String: Any] = [
            "device": "MLYamNet2MIDI",
            "version": "sceneMap-v1"
        ]
        if !programMapByLabel.isEmpty { body["programMap"] = programMapByLabel }
        if !programMapByIndex.isEmpty { body["programMapByIndex"] = programMapByIndex }
        if fallbackProgram >= 0 { body["defaultProgram"] = min(127, max(0, fallbackProgram)) }
        if let json = try? JSONSerialization.data(withJSONObject: body) {
            var payload: [UInt8] = [0x7E, 0x7F, 0x0D, 0x7C]
            payload.append(contentsOf: json)
            let reply = packSysEx7UMP(group: group, bytes: payload)
            try? transport.send(umpWords: reply)
            print("[ci] published mapping snapshot (\(programMapByLabel.count) labels, \(programMapByIndex.count) indices)")
        }
    }

    // MARK: - SysEx7 decode
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
}
