#if canImport(Midi2SamplerDSP)
import Foundation
import AVFoundation
import Midi2SamplerDSP

final class SamplerSynth: LocalRenderSynth {
    private let engine = AVAudioEngine()
    private var sampleRate: Double = 44100
    private var node: AVAudioSourceNode!
    private let lock = NSLock()
    private var active: [UInt8: (phase: Double, freq: Double, amp: Double, v2: UInt16)] = [:]
    private var proc = RealTimeNoteProcessor()

    init() {
        let outFmt = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outFmt.sampleRate
        proc.sampleRate = Float(sampleRate)
        node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let n = Int(frameCount)
            var mono = [Float](repeating: 0, count: n)
            self.lock.lock()
            let v2 = self.active.values.first?.v2 ?? 0
            self.proc.setControls(velocity2: v2, timbre: nil, pressure: nil)
            for frame in 0..<n {
                var sum: Double = 0
                for (k, v) in self.active { var e = v; sum += sin(e.phase) * e.amp; e.phase += 2.0 * .pi * e.freq / self.sampleRate; self.active[k] = e }
                mono[frame] = Float(sum * 0.2)
            }
            self.lock.unlock()
            removeDCInPlace(&mono)
            self.proc.processBlock(&mono)
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buf in abl { let ptr = buf.mData!.assumingMemoryBound(to: Float.self); for i in 0..<n { ptr[i] = mono[i] } }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
    }
    func start() { try? engine.start() }
    func stop() { engine.stop() }
    func noteOn(note: UInt8, velocity: UInt8) {
        let freq = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        let amp = Double(max(1, Int(velocity))) / 127.0
        let v2 = UInt16(Int(velocity) * 129)
        lock.lock(); active[note] = (phase: 0, freq: freq, amp: amp, v2: v2); lock.unlock()
    }
    func noteOff(note: UInt8) { lock.lock(); active.removeValue(forKey: note); lock.unlock() }
}
#endif
