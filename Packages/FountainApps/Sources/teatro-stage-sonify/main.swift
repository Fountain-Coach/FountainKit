import Foundation
import FountainAudioEngine
import TeatroPhysics
import teatro_stage_sonify_support

#if canImport(XCTest)
// Skip executable entrypoint when building tests; logic lives in the support module.
public func _teatroStageSonifyTestEntrypoint() {}
#else
@MainActor
@main
struct TeatroStageSonifyMain {
    static func main() {
        // Choose audio backend: SDLKitAudio via FountainAudioEngine if available, otherwise CoreAudio tone engine.
        enum Backend {
            case fountain
            case simple(SimpleToneEngine)
        }

        let backendChoice = ProcessInfo.processInfo.environment["FK_SONIFY_BACKEND"]?.lowercased()
        let backend: Backend
        #if canImport(SDLKitAudio)
        if backendChoice == "simple" {
            backend = Self.makeSimpleBackend()
        } else {
            do {
                try FountainAudioEngine.shared.start()
                FountainAudioEngine.shared.setParam(name: "engine.masterGain", value: 0.45)
                FountainAudioEngine.shared.setParam(name: "drone.amp", value: 0.4)
                FountainAudioEngine.shared.setParam(name: "drone.lpfHz", value: 2200)
                FountainAudioEngine.shared.setParam(name: "fx.delay.mix", value: 0.18)
                backend = .fountain
            } catch {
                fputs("[teatro-stage-sonify] FountainAudioEngine failed: \(error). Falling back to CoreAudio tone.\n", stderr)
                backend = Self.makeSimpleBackend()
            }
        }
        #else
        backend = Self.makeSimpleBackend()
        #endif

        let rig = TPPuppetRig()
        var state = SonifyState(
            time: 0,
            lastSnap: rig.snapshot(),
            lastEnergy: EnergySnapshot(time: 0, barHeight: 15, limbEnergy: 0),
            tickCount: 0
        )

        Task { @MainActor in
            while true {
                let dt = 1.0 / 60.0
                let result = sonifyTick(state: &state, rig: rig, dt: dt)

                switch backend {
                case .fountain:
                    FountainAudioEngine.shared.setParam(name: "frequency.hz", value: result.freq)
                    FountainAudioEngine.shared.setParam(name: "engine.masterGain", value: result.gain)
                    FountainAudioEngine.shared.setParam(name: "breath.level", value: clamp(result.energy * 0.02, min: 0.01, max: 0.5))
                    if result.energy > result.prevEnergy * 1.4 && result.energy > 8 {
                        let midiNote: UInt8 = UInt8(clamp(60 + Int(result.snap.bar.y), min: 48, max: 84))
                        let vel: UInt8 = UInt8(clamp(Int(80 + result.energy * 2), min: 40, max: 127))
                        FountainAudioEngine.shared.noteOn(note: midiNote, velocity: vel)
                    }
                case .simple(let simple):
                    simple.setFrequency(result.freq)
                    simple.setGain(result.gain)
                    if result.energy > result.prevEnergy * 1.4 && result.energy > 8 {
                        let vel: UInt8 = UInt8(clamp(Int(80 + result.energy * 2), min: 40, max: 127))
                        simple.noteOn(velocity: vel)
                    }
                }

                if state.tickCount % 120 == 0 {
                    let fmtGain = String(format: "%.2f", result.gain)
                    let fmtEnergy = String(format: "%.2f", result.energy)
                    let fmtFreq = String(format: "%.1f", result.freq)
                    print("[teatro-stage-sonify] t=\(String(format: "%.2f", state.time)) freq=\(fmtFreq)Hz gain=\(fmtGain) energy=\(fmtEnergy) backend=\(backendChoice ?? "auto")")
                }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }

        RunLoop.main.run()
    }

    @MainActor
    private static func makeSimpleBackend() -> Backend {
        do {
            let simple = try SimpleToneEngine()
            try simple.start()
            fputs("[teatro-stage-sonify] SDLKitAudio unavailable; using CoreAudio tone engine (audible). Install SDL2 + set FK_USE_SDLKIT=1 to use FountainAudioEngine.\n", stderr)
            return .simple(simple)
        } catch {
            fputs("[teatro-stage-sonify] CoreAudio fallback failed: \(error). Running silent.\n", stderr)
            return .simple(try! SimpleToneEngine()) // worst-case silent if start fails later
        }
    }
}
#endif
