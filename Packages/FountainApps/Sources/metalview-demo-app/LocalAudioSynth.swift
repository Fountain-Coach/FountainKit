import Foundation
import AVFoundation

final class LocalAudioSynth {
    private let engine = AVAudioEngine()
    private lazy var source: AVAudioSourceNode = {
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in abl { buffer.mData?.assumingMemoryBound(to: Float.self).initialize(repeating: 0, count: Int(frameCount)) }

            self.lock.lock()
            defer { self.lock.unlock() }

            if self.voices.isEmpty { return noErr }

            let sr = self.sampleRate
            let twoPiOverSR = 2.0 * Double.pi / sr
            for frame in 0..<Int(frameCount) {
                var s: Double = 0.0
                // Work on a stable key list to avoid mutating while iterating
                let keys = Array(self.voices.keys)
                for note in keys {
                    guard var v = self.voices[note] else { continue }
                    // Simple linear amp ramp
                    let ramp = 0.0008
                    if abs(v.targetAmp - v.amp) > ramp {
                        v.amp += (v.targetAmp > v.amp ? ramp : -ramp)
                    } else { v.amp = v.targetAmp }

                    // Pitch bend application (assume +/- 2 semitones for now)
                    let bendSemis = self.globalPitchBend * 2.0
                    let bentFreq = v.freq * pow(2.0, bendSemis/12.0)
                    v.phase += bentFreq * twoPiOverSR
                    if v.phase > 2.0 * Double.pi { v.phase -= 2.0 * Double.pi }
                    s += sin(v.phase) * v.amp
                    // Remove fully silent voices
                    if v.targetAmp == 0.0 && v.amp < 0.0001 {
                        self.voices.removeValue(forKey: note)
                    } else {
                        self.voices[note] = v
                    }
                }
                let sample = Float(s * self.volume)
                for buffer in abl {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = sample
                }
            }
            return noErr
        }
        return node
    }()
    private let sampleRate: Double

    private var voices: [UInt8: Voice] = [:] // note -> voice
    private var globalPitchBend: Double = 0.0 // [-1, +1] semitones range scaled later
    private var volume: Double = 0.2
    private let lock = NSLock()

    private struct Voice {
        var phase: Double
        var freq: Double
        var amp: Double
        var targetAmp: Double
    }

    init?() {
        let output = engine.outputNode
        let format = output.inputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000.0

        let hwFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(source)
        engine.connect(source, to: output, format: hwFormat)
        engine.prepare()
    }

    func start() {
        guard !engine.isRunning else { return }
        do { try engine.start() } catch { print("[LocalAudioSynth] start error: \(error)") }
    }

    func stop() {
        engine.stop()
        lock.lock(); voices.removeAll(); lock.unlock()
    }

    func setVolume(_ v: Double) { volume = max(0, min(1, v)) }

    func noteOn(note: UInt8, velocity: UInt8) {
        let freq = Self.midiNoteToFreq(Int(note))
        let amp = Double(velocity) / 127.0
        lock.lock(); defer { lock.unlock() }
        voices[note] = Voice(phase: 0, freq: freq, amp: 0.0, targetAmp: amp)
    }

    func noteOff(note: UInt8) {
        lock.lock(); defer { lock.unlock() }
        if var v = voices[note] { v.targetAmp = 0.0; voices[note] = v }
    }

    func pitchBend14(_ value: UInt16) {
        // Map 0..16383 to -1..+1
        let norm = (Double(value) / 8191.5) - 1.0
        lock.lock(); globalPitchBend = norm; lock.unlock()
    }

    private static func midiNoteToFreq(_ note: Int) -> Double {
        440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
    }
}

// Minimal macOS shim so we can compile without AVAudioSession on macOS
private enum AVAudioSessionLike {
    static var shared: AnyObject? { return NSObject() }
}
