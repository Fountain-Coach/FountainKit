import Foundation
import AVFoundation

/// Minimal CoreAudio-backed tone engine used when SDLKitAudio is unavailable.
/// Not a full synth, just enough to render the sonifier mappings audibly.
final class SimpleToneEngine {
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let freqHz = AtomicDouble(220.0)
    private let gain = AtomicDouble(0.2)
    private let noteEnv = AtomicDouble(0.35) // steady bed so we always hear output
    private let sourceNode: AVAudioSourceNode

    init(sampleRate: Double = 48000) throws {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        var phase: Double = 0
        let twoPi = 2.0 * Double.pi
        let freqRef = freqHz
        let gainRef = gain
        let envRef = noteEnv
        let sr = format.sampleRate
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let freq = freqRef.load()
            let g = gainRef.load()
            let env = envRef.load()
            let phaseInc = twoPi * freq / sr
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<frames {
                let envNow = min(1.0, env)
                let sample = sin(phase) * g * envNow
                phase += phaseInc
                if phase > twoPi { phase -= twoPi }
                for buf in abl {
                    let ptr = buf.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = Float(sample)
                }
            }
            return noErr
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
    }

    func start() throws {
        try engine.start()
        // Kick a short blip so the user hears something immediately.
        noteOn(velocity: 100)
    }

    func setFrequency(_ f: Double) { freqHz.store(max(20, min(4000, f))) }
    func setGain(_ g: Double) { gain.store(max(0, min(1.0, g))) }

    /// Fire a short percussive blip.
    func noteOn(velocity: UInt8) {
        let v = Double(max(1, min(127, Int(velocity)))) / 127.0
        noteEnv.store(min(1.0, v))
        // Simple decay on a background queue back to the bed level.
        let envRef = noteEnv
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            envRef.store(0.35)
        }
    }
}

// Tiny atomic wrapper for doubles.
final class AtomicDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double
    init(_ v: Double) { value = v }
    func load() -> Double { lock.lock(); let v = value; lock.unlock(); return v }
    func store(_ v: Double) { lock.lock(); value = v; lock.unlock() }
}
