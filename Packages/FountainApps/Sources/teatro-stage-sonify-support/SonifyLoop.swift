import Foundation
import TeatroPhysics

public struct EnergySnapshot {
    public var time: Double
    public var barHeight: Double
    public var limbEnergy: Double

    public init(time: Double, barHeight: Double, limbEnergy: Double) {
        self.time = time
        self.barHeight = barHeight
        self.limbEnergy = limbEnergy
    }
}

public struct SonifyState {
    public var time: Double
    public var lastSnap: TPPuppetSnapshot
    public var lastEnergy: EnergySnapshot
    public var tickCount: Int

    public init(time: Double, lastSnap: TPPuppetSnapshot, lastEnergy: EnergySnapshot, tickCount: Int) {
        self.time = time
        self.lastSnap = lastSnap
        self.lastEnergy = lastEnergy
        self.tickCount = tickCount
    }
}

/// Computes one audio-mapping tick from the puppet snapshot.
/// Returns (freqHz, gain, energy, prevEnergy, snap) so callers can emit audio on the correct thread.
public func sonifyTick(state: inout SonifyState, rig: TPPuppetRig, dt: Double) -> (freq: Double, gain: Double, energy: Double, prevEnergy: Double, snap: TPPuppetSnapshot) {
    state.time += dt
    rig.step(dt: dt, time: state.time)
    let snap = rig.snapshot()

    // Bar height maps to base frequency (rough 200–700 Hz band).
    let freq = clamp(200.0 + snap.bar.y * 20.0, min: 120.0, max: 900.0)

    // Limb energy = sum of hand/foot velocity magnitudes.
    let energy = energyBetween(last: state.lastSnap, now: snap, dt: dt)
    let gain = clamp(energy * 0.05, min: 0.02, max: 0.9)

    let prevEnergy = state.lastEnergy.limbEnergy
    state.lastEnergy = EnergySnapshot(time: state.time, barHeight: snap.bar.y, limbEnergy: energy)
    state.lastSnap = snap
    state.tickCount &+= 1

    return (freq, gain, energy, prevEnergy, snap)
}

public func energyBetween(last: TPPuppetSnapshot, now: TPPuppetSnapshot, dt: Double) -> Double {
    guard dt > 0 else { return 0 }
    func vel(_ a: TPVec3, _ b: TPVec3) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz) / dt
    }
    let limbs: [(TPVec3, TPVec3)] = [
        (now.handL, last.handL), (now.handR, last.handR),
        (now.footL, last.footL), (now.footR, last.footR)
    ]
    return limbs.reduce(0.0) { $0 + vel($1.0, $1.1) }
}

public func clamp<T: Comparable>(_ v: T, min lo: T, max hi: T) -> T {
    max(lo, min(hi, v))
}
