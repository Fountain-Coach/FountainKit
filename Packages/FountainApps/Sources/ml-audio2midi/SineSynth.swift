import Foundation
import AVFoundation

protocol LocalRenderSynth: AnyObject {
    func start()
    func stop()
    func noteOn(note: UInt8, velocity: UInt8)
    func noteOff(note: UInt8)
    func pitchBend14(_ v14: UInt16)
}

final class SineSynth: LocalRenderSynth {
    private let engine = AVAudioEngine()
    private var sampleRate: Double = 44100
    private var active: [UInt8: (phase: Double, freq: Double, amp: Double)] = [:]
    private var pbRatio: Double = 1.0
    private var node: AVAudioSourceNode!
    private let lock = NSLock()
    init() {
        let outFmt = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outFmt.sampleRate
        node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let n = Int(frameCount)
            var mono = [Float](repeating: 0, count: n)
            for frame in 0..<n {
                var sample: Double = 0
                self.lock.lock()
                for (k, v) in self.active { var entry = v; sample += sin(entry.phase) * entry.amp; entry.phase += 2.0 * .pi * entry.freq * self.pbRatio / self.sampleRate; self.active[k] = entry }
                self.lock.unlock()
                mono[frame] = Float(sample * 0.2)
            }
            #if canImport(Midi2SamplerDSP)
            removeDCInPlace(&mono)
            #endif
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
        lock.lock(); active[note] = (phase: 0, freq: freq, amp: amp); lock.unlock()
    }
    func noteOff(note: UInt8) { lock.lock(); active.removeValue(forKey: note); lock.unlock() }
    func pitchBend14(_ v14: UInt16) {
        let norm = (Double(v14) / 16383.0) * 2.0 - 1.0
        let semis = norm * 2.0
        pbRatio = pow(2.0, semis / 12.0)
    }
}

// startSynthIfNeeded is implemented inside Runner (main.swift)
