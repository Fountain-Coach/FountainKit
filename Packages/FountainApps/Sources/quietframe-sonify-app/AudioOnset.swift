import Foundation
import Accelerate
import FountainAudioEngine

@MainActor final class AudioOnsetToNotes {
    static let shared = AudioOnsetToNotes()
    private var enabled = false
    private var lastOnsetNs: UInt64 = 0
    private var cooldownMs: Double = 120.0
    private var thresholdRMS: Float = 0.02 // conservative; engine master gain gates loudness
    private var noteHoldMs: Double = 160.0
    private var pendingOff: [(UInt8, UInt64)] = [] // (note, dueNs)

    func start() {
        guard !enabled else { return }
        enabled = true
        FountainAudioEngine.installAudioTap { [weak self] lptr, rptr, n, sr in
            guard let self else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            // Quick RMS over interleaved channels
            var sum: Float = 0
            for i in 0..<n { let l = lptr[i]; let r = rptr[i]; let s = 0.5*(l*l + r*r); sum += s }
            let rms = sqrt(max(0, sum / Float(n)))
            // Schedule note offs
            if !self.pendingOff.isEmpty {
                let due = self.pendingOff
                self.pendingOff.removeAll(keepingCapacity: true)
                for (note, t) in due { if now >= t { FountainAudioEngine.shared.noteOff(note: note) } else { self.pendingOff.append((note, t)) } }
            }
            // Onset detect with cooldown
            let sinceMs = Double(now &- self.lastOnsetNs) / 1_000_000.0
            if rms > self.thresholdRMS && sinceMs > self.cooldownMs {
                self.lastOnsetNs = now
                // Estimate fundamental from zero-crossing rate (coarse but fast)
                var crosses = 0
                var prev: Float = lptr[0]
                for i in 1..<n { let s = lptr[i]; if (s >= 0 && prev < 0) || (s < 0 && prev >= 0) { crosses += 1 }; prev = s }
                let estHz = max(50.0, min(sr*0.45, (Double(crosses) / Double(n)) * (sr / 2.0)))
                // Map to MIDI, but keep exact Hz for sonification
                let midi = 69.0 + 12.0 * log2(estHz / 440.0)
                let note = UInt8(max(0, min(127, Int(midi.rounded()))))
                let vel = UInt8(min(127, max(20, Int((Double(rms) * 6400.0).rounded()))))
                Task { @MainActor in
                    FountainAudioEngine.shared.noteOn(hz: estHz, midiNote: note, velocity: vel)
                    MidiMonitorStore.shared.add(String(format: "Onset→Hz %.1f n=%d v=%d", estHz, note, vel))
                    SidecarBridge.shared.sendNoteEvent(["event":"noteOn","note":Int(note),"velocity":Int(vel),"hz":Int(estHz.rounded()),"channel":0,"group":0,"source":"onset"])            
                }
                let dueNs = now + UInt64(self.noteHoldMs * 1_000_000.0)
                self.pendingOff.append((note, dueNs))
            }
        }
    }

    func stop() {
        enabled = false
        FountainAudioEngine.installAudioTap(nil)
    }

    // MARK: - Controls (CI/PE via sink.setUniform)
    func setThresholdRMS(_ v: Float) { thresholdRMS = max(0.0001, min(1.0, v)) }
    func setCooldownMs(_ v: Double) { cooldownMs = max(10.0, min(2000.0, v)) }
    func setNoteHoldMs(_ v: Double) { noteHoldMs = max(20.0, min(2000.0, v)) }
}

private extension Int {
    static var now: Int { Int(DispatchTime.now().uptimeNanoseconds & 0x7fffffff) }
}
