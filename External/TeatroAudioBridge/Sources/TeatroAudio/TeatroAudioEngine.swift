import Foundation
import AVFoundation

// Minimal, SPM-friendly TeatroAudio replacement that provides a
// compatible API surface for in-app synthesis on macOS.
// It intentionally does not depend on TeatroCore to remain standalone.

public final class TeatroAudioEngine {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var started = false

    public init() throws {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        started = true
        // Try to load a common macOS SoundFont if available; otherwise rely on the default timbre.
        let defaultSF2 = "/Library/Sounds/GeneralUser.sf2"
        if FileManager.default.fileExists(atPath: defaultSF2) {
            let url = URL(fileURLWithPath: defaultSF2)
            try? sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0x79, bankLSB: 0x00)
        }
    }

    public func start() { if !started { try? engine.start(); started = true } }
    public func stop() { engine.stop(); started = false }

    public func setMasterVolume(_ v: Double) {
        let value = max(0, min(1, v))
        engine.mainMixerNode.outputVolume = Float(value)
    }

    // MIDI 1.0 style entry points (compatible with original TeatroAudioEngine)
    public func noteOn(note: UInt8, vel: UInt8, ch: UInt8) {
        sampler.startNote(note, withVelocity: vel, onChannel: ch)
    }

    public func noteOff(note: UInt8, ch: UInt8) {
        sampler.stopNote(note, onChannel: ch)
    }

    public func controlChange(cc: UInt8, value: UInt8, ch: UInt8) {
        sampler.sendController(cc, withValue: value, onChannel: ch)
    }
}

