import Foundation

protocol SynthDevice: AnyObject {
    func start()
    func stop()
    func setVolume(_ v: Double)
    func noteOn(note: UInt8, velocity: UInt8)
    func noteOff(note: UInt8)
    func pitchBend14(_ value: UInt16)
}

// Default local implementation (fallback)
final class LocalAudioSynthDevice: SynthDevice {
    private var impl: LocalAudioSynth?
    init() { impl = LocalAudioSynth() }
    func start() { impl?.start() }
    func stop() { impl?.stop(); impl = nil }
    func setVolume(_ v: Double) { impl?.setVolume(v) }
    func noteOn(note: UInt8, velocity: UInt8) { impl?.noteOn(note: note, velocity: velocity) }
    func noteOff(note: UInt8) { impl?.noteOff(note: note) }
    func pitchBend14(_ value: UInt16) { impl?.pitchBend14(value) }
}

// Teatro-backed synth (compiled only when available)
#if canImport(TeatroAudio)
import TeatroAudio

final class TeatroSynthDevice: SynthDevice {
    private let engine: TeatroAudioEngine
    private var volume: Double = 0.2
    init?() {
        guard let eng = try? TeatroAudioEngine() else { return nil }
        self.engine = eng
    }
    func start() {}
    func stop() {}
    func setVolume(_ v: Double) { volume = max(0, min(1, v)); engine.controlChange(cc: 7, value: UInt8(volume * 127), ch: 0) }
    func noteOn(note: UInt8, velocity: UInt8) { engine.noteOn(note: note, vel: velocity, ch: 0) }
    func noteOff(note: UInt8) { engine.noteOff(note: note, ch: 0) }
    func pitchBend14(_ value: UInt16) { /* not exposed on engine; ignore for now */ }
}
#endif
