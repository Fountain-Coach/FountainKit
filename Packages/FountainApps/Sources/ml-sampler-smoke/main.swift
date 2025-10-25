import Foundation
import AVFoundation
import ArgumentParser

enum Wave: String, ExpressibleByArgument { case sine, square, saw, triangle }

@main
struct SamplerSmoke: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ml-sampler-smoke",
        abstract: "Noninteractive in-process synth demo: scale/chord/arp with simple waveforms"
    )

    @Option(name: .shortAndLong, help: "Pattern: scale|chord|arp") var pattern: String = "scale"
    @Option(name: .shortAndLong, help: "Root frequency in Hz (e.g. 261.63 for C4)") var freq: Double = 261.63
    @Option(name: .long, help: "Chord intervals (semitones) for chord/arp, comma-separated, e.g. 0,4,7") var intervals: String = "0,4,7"
    @Option(name: .shortAndLong, help: "Waveform: sine|square|saw|triangle") var wave: Wave = .sine
    @Option(name: .long, help: "BPM for arp/scale stepping") var bpm: Double = 120
    @Option(name: .long, help: "Duration seconds") var duration: Double = 5.0
    @Option(name: .long, help: "Amplitude 0..1") var amp: Double = 0.2

    func run() throws {
        let engine = AVAudioEngine()
        let fmt = engine.outputNode.outputFormat(forBus: 0)
        let sr = fmt.sampleRate
        let blockSec = 60.0 / max(1.0, bpm)
        let ivals = intervals.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        // Precompute pattern frequencies
        func semitone(_ s: Double) -> Double { freq * pow(2.0, s/12.0) }
        let patternFreqs: [[Double]]
        switch pattern.lowercased() {
        case "chord":
            patternFreqs = [ivals.map(semitone)]
        case "arp":
            patternFreqs = ivals.map { [semitone($0)] }
        default: // scale (0..7)
            patternFreqs = (0..<8).map { [semitone(Double($0))] }
        }

        func w(_ f: Double, _ t: Double) -> Double {
            switch wave {
            case .sine: return sin(2.0 * .pi * f * t)
            case .square: return sin(2.0 * .pi * f * t) >= 0 ? 1.0 : -1.0
            case .saw:
                let x = t*f
                return 2.0 * (x - floor(0.5 + x))
            case .triangle:
                let x = t*f
                return 2.0 * abs(2.0 * (x - floor(0.5 + x))) - 1.0
            }
        }

        var stepIndex = 0
        var frameCounter: Int64 = 0
        let framesPerStep = Int64(sr * blockSec)
        let node = AVAudioSourceNode { _, _, frameCount, abl -> OSStatus in
            let n = Int(frameCount)
            let out = UnsafeMutableAudioBufferListPointer(abl)
            for buf in out { memset(buf.mData!, 0, Int(buf.mDataByteSize)) }
            let freqs = patternFreqs[min(stepIndex, patternFreqs.count-1)]
            for i in 0..<n {
                let t = Double(frameCounter + Int64(i)) / sr
                var s = 0.0
                for f in freqs { s += w(f, t) }
                s = (s / Double(max(1, freqs.count))) * amp
                for buf in out {
                    let ptr = buf.mData!.assumingMemoryBound(to: Float.self)
                    ptr[i] = Float(s)
                }
            }
            frameCounter += Int64(n)
            while frameCounter >= Int64(stepIndex+1) * framesPerStep {
                stepIndex = (stepIndex + 1) % max(1, patternFreqs.count)
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        try engine.start()
        print("[sampler-smoke] pattern=\(pattern) wave=\(wave.rawValue) freq=\(freq) bpm=\(bpm) dur=\(duration)")
        Thread.sleep(forTimeInterval: duration)
        engine.stop()
    }
}
