import Foundation

#if canImport(SDLKitAudio)
import SDLKitAudio

// SDLKitAudio-backed, lock-light synth engine implementing the QuietFrame layers.
@MainActor public final class FountainAudioEngine {
    public static let shared = FountainAudioEngine()

    // MARK: - SDL state
    private var host: SDLKitAudioHost? = nil
    private var sampleRate: Double = 48000

    // MARK: - Parameters (Atomic)
    private let engMaster = AtomicF(0.0)         // engine.masterGain [0..1]
    private let engMuted  = AtomicF(0.0)         // audio.muted 0|1

    private let baseFreq  = AtomicF(440.0)       // frequencyHz

    // Drone
    private let droneAmp  = AtomicF(0.2)
    private let droneLPF  = AtomicF(1200.0)
    private let droneReso = AtomicF(0.0)         // reserved
    private let droneDet  = AtomicF(0.01)        // detune (fraction)
    private let droneMixSaw = AtomicF(0.0)       // reserved

    // Clock
    private let clockLvl  = AtomicF(0.15)
    private let clockDiv  = AtomicF(2.0)         // 2=1/8, 1=1/4, etc.
    private let clockGhost = AtomicF(0.15)

    // Breath
    private let breathLvl = AtomicF(0.08)
    private let breathCtr = AtomicF(1800.0)
    private let breathWid = AtomicF(800.0)

    // Overtones
    private let overMix   = AtomicF(0.0)
    private let overIdx   = AtomicF(0.0)         // reserved
    private let overCho   = AtomicF(0.0)         // reserved

    // FX
    private let fxPlate   = AtomicF(0.0)
    private let fxDelay   = AtomicF(0.04)
    private let fxFeed    = AtomicF(0.2)
    private let fxLimitTh = AtomicF(0.9)

    // Act / harmony
    private let actSection = AtomicF(1.0)
    private let tempoBPM   = AtomicF(96.0)
    private let keyIndex   = AtomicF(0.0)
    private let scaleIndex = AtomicF(0.0)

    // MARK: - Runtime state (audio thread)
    private var dronePhase1: Float = 0
    private var dronePhase2: Float = 0
    private var lpfState: Float = 0

    private var clockPhase: Float = 0
    private var clockEnv: Float = 0
    private var clockEnvDecay: Float = 0.0

    private var hpState: Float = 0
    private var lpState: Float = 0

    private var delayBuf: [Float] = []
    private var delayIdx: Int = 0

    // MARK: - Audio tap (optional)
    // Lightweight callback invoked on the audio render thread. Callers must copy data quickly.
    private static var _audioTapLock = NSLock()
    private static var _audioTap: ((UnsafePointer<Float>, UnsafePointer<Float>, Int, Double) -> Void)? = nil
    public static func installAudioTap(_ tap: ((UnsafePointer<Float>, UnsafePointer<Float>, Int, Double) -> Void)?) {
        _audioTapLock.lock(); _audioTap = tap; _audioTapLock.unlock()
    }

    // MARK: - Public API
    public func start(sampleRate: Double = 48000, blockSize: Int32 = 256) throws {
        let host = SDLKitAudioHost(sampleRate: sampleRate, channels: 2, framesPerBuffer: Int(blockSize)) { [weak self] lptr, rptr, n, sr in
            guard let self else { return }

            // Precompute delay buffer length from tempo (1/8th note)
            let bpm = max(30.0, min(240.0, Double(self.tempoBPM.load())))
            let eighthSec = (60.0 / bpm) / 2.0
            let needLen = max(1, Int(eighthSec * sr) + 4)
            if self.delayBuf.count != needLen { self.delayBuf = Array(repeating: 0, count: needLen); self.delayIdx = 0 }

            // Clock env decay for ~15 ms
            self.clockEnvDecay = exp(-1.0 / Float(sr * 0.015))

            let master = self.engMuted.load() >= 0.5 ? 0.0 : self.engMaster.load()
            if master <= 0.0001 {
                for i in 0..<n { lptr[i] = 0; rptr[i] = 0 }
                return
            }

            // Cached params
            let fBase = self.baseFreq.load()
            let det = self.droneDet.load()
            let lpfHz = max(50.0, min(Float(self.droneLPF.load()), Float(sr*0.45)))
            let lpfA = exp(-2.0 * .pi * (lpfHz / Float(sr)))
            let droneA = self.droneAmp.load()

            let clkLvl = self.clockLvl.load()
            let clkDiv = max(1.0, self.clockDiv.load())
            let ghostP = max(0.0, min(1.0, self.clockGhost.load()))

            let brLvl = self.breathLvl.load()
            let brCtr = max(100.0, min(Float(self.breathCtr.load()), Float(sr*0.4)))
            let brWid = max(50.0, min(Float(self.breathWid.load()), Float(sr*0.35)))

            let overM = self.overMix.load()

            let dMix = self.fxDelay.load()
            let dFb  = max(0.0, min(0.95, self.fxFeed.load()))
            let limitT = max(0.1, min(1.5, self.fxLimitTh.load()))

            for i in 0..<n {
                // Drone: two detuned sines → simple LPF
                let f1 = Float(fBase) * (1.0 - Float(det) * 0.01)
                let f2 = Float(fBase) * (1.0 + Float(det) * 0.01)
                let d1 = Float(2.0 * .pi) * (f1 / Float(sr))
                let d2 = Float(2.0 * .pi) * (f2 / Float(sr))
                self.dronePhase1 += d1; if self.dronePhase1 > Float(2.0 * .pi) { self.dronePhase1 -= Float(2.0 * .pi) }
                self.dronePhase2 += d2; if self.dronePhase2 > Float(2.0 * .pi) { self.dronePhase2 -= Float(2.0 * .pi) }
                var drone = (sinf(self.dronePhase1) + sinf(self.dronePhase2)) * 0.5
                self.lpfState = (1 - lpfA) * drone + lpfA * self.lpfState
                drone = self.lpfState * Float(droneA)

                // Clock
                let beatsPerSec = Float(bpm / 60.0)
                let ticksPerSec = beatsPerSec * Float(1.0 / clkDiv)
                self.clockPhase += ticksPerSec / Float(sr)
                if self.clockPhase >= 1.0 {
                    self.clockPhase -= 1.0
                    if Float.random(in: 0...1) > Float(ghostP) { self.clockEnv = 1.0 }
                }
                self.clockEnv *= self.clockEnvDecay
                let clk = sinf(self.dronePhase1 * 10.0) * self.clockEnv * Float(clkLvl)

                // Breath noise → HP → LP
                let noise = Float.random(in: -1...1)
                let hpCut = max(10.0, brCtr - brWid)
                let aHP = exp(-2.0 * .pi * (hpCut / Float(sr)))
                self.hpState = (1 - aHP) * noise + aHP * self.hpState
                var breath = noise - self.hpState
                let lpCut = min(Float(sr*0.45), brCtr + brWid)
                let aLP = exp(-2.0 * .pi * (lpCut / Float(sr)))
                self.lpState = (1 - aLP) * breath + aLP * self.lpState
                breath = self.lpState * Float(brLvl)

                // Overtones
                var over: Float = 0
                for h in 2...6 { let p = Float(h); over += sinf(self.dronePhase1 * p) * (1.0 / p) }
                over *= Float(overM) * 0.6

                // Sum
                var s = drone + clk + breath + over
                if !self.delayBuf.isEmpty {
                    let rd = self.delayIdx
                    let tapped = self.delayBuf[rd]
                    let wr = (rd + 1) % self.delayBuf.count
                    self.delayBuf[wr] = s + tapped * Float(dFb)
                    self.delayIdx = wr
                    s = self.mix(s, tapped, t: Float(dMix))
                }
                s = self.softClip(s * Float(master), threshold: Float(limitT))
                lptr[i] = s; rptr[i] = s
            }
            // Publish to optional tap in interleaved form (fast copy in consumer)
            FountainAudioEngine._audioTapLock.lock()
            let tap = FountainAudioEngine._audioTap
            FountainAudioEngine._audioTapLock.unlock()
            if let tap { tap(lptr, rptr, n, Double(sr)) }
        }
        self.sampleRate = sampleRate
        try host.start()
        self.host = host
    }

    public func stop() { host?.stop(); host = nil }

    // Back-compat mapping used by UI saliency
    public func setFrequency(_ f: Double) { baseFreq.store(Float(max(20, min(4000, f)))) }
    public func setAmplitude(_ a: Double) { engMaster.store(Float(max(0, min(1.0, a)))) }

    public func setParam(name: String, value: Double) {
        switch name {
        case "engine.masterGain": engMaster.store(Float(clamp01(value)))
        case "audio.muted": engMuted.store(value >= 0.5 ? 1.0 : 0.0)
        case "drone.amp": droneAmp.store(Float(clamp01(value)))
        case "drone.lpfHz": droneLPF.store(Float(max(50.0, min(8000.0, value))))
        case "drone.reso": droneReso.store(Float(clamp01(value)))
        case "drone.detune": droneDet.store(Float(max(0.0, min(0.1, value))))
        case "drone.mixSaw": droneMixSaw.store(Float(clamp01(value)))
        case "clock.level": clockLvl.store(Float(clamp01(value)))
        case "clock.div": clockDiv.store(Float(max(1.0, min(8.0, value))))
        case "clock.ghostProbability": clockGhost.store(Float(clamp01(value)))
        case "breath.level": breathLvl.store(Float(clamp01(value)))
        case "breath.centerHz": breathCtr.store(Float(max(100.0, min(6000.0, value))))
        case "breath.width": breathWid.store(Float(max(50.0, min(4000.0, value))))
        case "overtones.mix": overMix.store(Float(clamp01(value)))
        case "overtones.modIndex": overIdx.store(Float(clamp01(value)))
        case "overtones.chorus": overCho.store(Float(clamp01(value)))
        case "fx.plate.mix": fxPlate.store(Float(clamp01(value)))
        case "fx.delay.mix": fxDelay.store(Float(clamp01(value)))
        case "fx.delay.feedback": fxFeed.store(Float(clamp01(value)))
        case "fx.limiter.threshold": fxLimitTh.store(Float(max(0.1, min(1.5, value))))
        case "act.section": actSection.store(Float(max(0.0, min(9.0, value))))
        case "tempo.bpm": tempoBPM.store(Float(max(30.0, min(240.0, value))))
        case "harmony.key": keyIndex.store(Float(max(0.0, min(11.0, value))))
        case "harmony.scale": scaleIndex.store(Float(max(0.0, min(7.0, value))))
        case "frequency.hz": baseFreq.store(Float(max(20.0, min(4000.0, value))))
        default: break
        }
    }

    public func snapshot() -> [String: Any] {
        return [
            "engine.masterGain": Double(engMaster.load()),
            "audio.muted": Double(engMuted.load()),
            "drone.amp": Double(droneAmp.load()),
            "drone.lpfHz": Double(droneLPF.load()),
            "drone.reso": Double(droneReso.load()),
            "drone.detune": Double(droneDet.load()),
            "drone.mixSaw": Double(droneMixSaw.load()),
            "clock.level": Double(clockLvl.load()),
            "clock.div": Double(clockDiv.load()),
            "clock.ghostProbability": Double(clockGhost.load()),
            "breath.level": Double(breathLvl.load()),
            "breath.centerHz": Double(breathCtr.load()),
            "breath.width": Double(breathWid.load()),
            "overtones.mix": Double(overMix.load()),
            "overtones.modIndex": Double(overIdx.load()),
            "overtones.chorus": Double(overCho.load()),
            "fx.plate.mix": Double(fxPlate.load()),
            "fx.delay.mix": Double(fxDelay.load()),
            "fx.delay.feedback": Double(fxFeed.load()),
            "fx.limiter.threshold": Double(fxLimitTh.load()),
            "act.section": Double(actSection.load()),
            "tempo.bpm": Double(tempoBPM.load()),
            "harmony.key": Double(keyIndex.load()),
            "harmony.scale": Double(scaleIndex.load()),
            "frequency.hz": Double(baseFreq.load())
        ]
    }

    // MARK: - Private helpers
    private func mix(_ a: Float, _ b: Float, t: Float) -> Float { a * (1 - t) + b * t }
    private func softClip(_ x: Float, threshold: Float) -> Float {
        let t = max(0.001, threshold)
        let k: Float = 2.0 / t
        return tanh(x * k) / tanh(k)
    }
}

// Minimal atomic float (coarse), sufficient for UI→audio thread updates
fileprivate final class AtomicF {
    private var v: Float
    private let lock = NSLock()
    init(_ v: Float) { self.v = v }
    func store(_ nv: Float) { lock.lock(); v = nv; lock.unlock() }
    func load() -> Float { lock.lock(); let r = v; lock.unlock(); return r }
}

#else
// Fallback shim when SDLKit is not available (no-op engine)
@MainActor public final class FountainAudioEngine {
    public static let shared = FountainAudioEngine()
    public func start(sampleRate: Double = 48000, blockSize: Int32 = 256) throws {}
    public func stop() {}
    public func setFrequency(_ f: Double) {}
    public func setAmplitude(_ a: Double) {}
    public func setParam(name: String, value: Double) {}
    public func snapshot() -> [String: Any] { [:] }
}
#endif

// Shared helpers
fileprivate func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }
